# 01_od_data.R
# Generate 20k origins and destinations per city weighted by building volume

library(duckdb)
library(sf)
library(dplyr)
sf_use_s2(FALSE)

data_dir <- path.expand("~/GIS/Sydney/data/test-pipeline")
target_cities <- c("Sydney")

# Map of cities to the S3 bucket tile name
tile_map <- list(
    Lisbon = "w010_n40_w005_n35",
    Sydney = "e150_s30_e155_s35",
    Paris = "e000_n50_e005_n45",
    Barcelona = "e000_n45_e005_n40"
)

# Function to fetch buildings from S3 parquet using exact bbox
fetch_building_points <- function(city_name, bbox, tile_name) {
    parquet_s3_path <- paste0("s3://us-west-2.opendata.source.coop/tge-labs/globalbuildingatlas-lod1/", tile_name, ".parquet")

    q_xmin <- bbox["xmin"]
    q_ymin <- bbox["ymin"]
    q_xmax <- bbox["xmax"]
    q_ymax <- bbox["ymax"]

    con <- dbConnect(duckdb())
    dbExecute(con, "INSTALL spatial; LOAD spatial; INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2'; SET preserve_insertion_order=false;")

    query <- paste0("
    SELECT * EXCLUDE (geometry),
           ST_AsWKB(TRY_CAST(geometry AS GEOMETRY)) as geom_wkb
    FROM read_parquet('", parquet_s3_path, "')
    WHERE bbox.xmin >= ", q_xmin, " AND bbox.xmax <= ", q_xmax, "
      AND bbox.ymin >= ", q_ymin, " AND bbox.ymax <= ", q_ymax)

    message(paste("Fetching data for", city_name, "..."))
    raw_data <- dbGetQuery(con, query) |>
        filter(!is.na(geom_wkb))
    dbDisconnect(con)

    if (nrow(raw_data) == 0) {
        return(NULL)
    }

    buildings_centroids <- raw_data %>%
        mutate(geometry = st_as_sfc(geom_wkb, crs = 4326)) %>%
        st_as_sf() %>%
        mutate(
            footprint_m2 = round(as.numeric(st_area(st_transform(., 3857)))),
            est_floors = pmax(1, round(height / 3)),
            total_floor_area_m2 = round(footprint_m2 * est_floors),
            volume_m3 = round(footprint_m2 * height)
        ) %>%
        st_make_valid() %>%
        st_centroid() %>%
        mutate(
            lon = st_coordinates(geometry)[, 1],
            lat = st_coordinates(geometry)[, 2]
        ) %>%
        st_drop_geometry() %>%
        st_as_sf(coords = c("lon", "lat"), crs = 4326) %>%
        select(id, height, est_floors, footprint_m2, total_floor_area_m2, volume_m3)

    return(buildings_centroids)
}

set.seed(42)

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)
    city_poly_path <- file.path(city_dir, paste0(city_lower, "_10km.gpkg"))

    if (!file.exists(city_poly_path)) {
        warning(paste("Missing poly for", city))
        next
    }

    city_poly <- st_read(city_poly_path, quiet = TRUE)
    bbox <- st_bbox(city_poly)
    tile_name <- tile_map[[city]]

    buildings <- fetch_building_points(city, bbox, tile_name)

    if (is.null(buildings) || nrow(buildings) == 0) {
        warning(paste("No buildings fetched for", city))
        next
    }

    # Filter precisely to the 10km polygon
    buildings_city <- buildings[city_poly, ]

    rm(buildings) # free memory
    gc()

    # Sample origins (unweighted)
    origins <- buildings_city |>
        slice_sample(n = 20000, replace = TRUE) |>
        select(volume_m3) |>
        rename(volume = volume_m3) |>
        mutate(id = row_number())

    # Sample destinations (weighted by building volume/area)
    destinations <- buildings_city |>
        slice_sample(n = 20000, weight_by = volume_m3, replace = TRUE) |>
        select(volume_m3) |>
        rename(volume = volume_m3) |>
        mutate(id = row_number())

    rm(buildings_city) # free memory
    gc()

    # Save lightweight files
    st_write(origins, file.path(city_dir, "origins.gpkg"), append = FALSE, delete_dsn = TRUE, quiet = TRUE)
    st_write(destinations, file.path(city_dir, "destinations.gpkg"), append = FALSE, delete_dsn = TRUE, quiet = TRUE)

    cat(paste("Successfully generated OD matrices for", city, "\n"))
}
