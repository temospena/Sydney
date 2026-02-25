# 02_od_data.R
# Generate 1000 origins and destinations per city weighted by building volume

library(duckdb)
library(sf)
library(dplyr)
sf_use_s2(FALSE)

# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run

# The city_list.txt is expected to be in the 'data' folder
if (requireNamespace("here", quietly = TRUE)) {
    city_list_path <- here::here("data/city_list.txt")
} else {
    city_list_path <- "data/city_list.txt"
    if (!file.exists(city_list_path)) city_list_path <- "../../data/city_list.txt"
}

# Read city list for tiles
city_list_tiles <- read.csv(city_list_path, header = FALSE) |>
    select(V1, V7) |>
    rename(city = V1, tile_name = V7)

# Function to fetch buildings from S3 parquet using exact bbox
fetch_building_points <- function(city_name, city_bbox, tile_name) {
    parquet_s3_path <- paste0("s3://us-west-2.opendata.source.coop/tge-labs/globalbuildingatlas-lod1/", tile_name, ".parquet")

    q_xmin <- city_bbox["xmin"]
    q_ymin <- city_bbox["ymin"]
    q_xmax <- city_bbox["xmax"]
    q_ymax <- city_bbox["ymax"]

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
        mutate(
            geometry = st_as_sfc(geom_wkb, crs = 4326),
            lon = (bbox$xmin + bbox$xmax) / 2,
            lat = (bbox$ymin + bbox$ymax) / 2
        ) %>%
        st_as_sf() %>%
        mutate(
            footprint_m2 = round(as.numeric(st_area(st_transform(., 3857)))),
            est_floors = pmax(1, round(height / 3)),
            total_floor_area_m2 = round(footprint_m2 * est_floors),
            volume_m3 = round(footprint_m2 * height)
        ) %>%
        st_drop_geometry() %>%
        st_as_sf(coords = c("lon", "lat"), crs = 4326) %>%
        select(id, height, est_floors, footprint_m2, total_floor_area_m2, volume_m3)

    return(buildings_centroids)
}

set.seed(42) # for reproducibility (because of reasons)

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

    # Robustly handle multiple cities with the same name (e.g., London UK vs London Canada)
    # Read full list to find all matches and their coordinates
    city_list_all <- read.csv(city_list_path, header = FALSE) |>
        rename(city = V1, lat = V2, lon = V3, tile_name = V7)

    matches <- city_list_all |> filter(city == !!city)

    if (nrow(matches) == 0) {
        warning(paste("No tile mapping found in city_list.txt for", city))
        next
    }

    if (nrow(matches) > 1) {
        # Differentiate by distance to the existing buffer center
        buf_centroid <- st_centroid(city_poly)
        matches_sf <- matches |> st_as_sf(coords = c("lon", "lat"), crs = 4326)
        dists <- st_distance(matches_sf, buf_centroid)
        tile_name <- matches$tile_name[which.min(dists)]
        cat(paste("    Multiple matches found for", city, "- Selected tile based on distance:", tile_name, "\n"))
    } else {
        tile_name <- matches$tile_name
    }

    if (is.na(tile_name) || tile_name == "") {
        warning(paste("Invalid tile name found in city_list.txt for", city))
        next
    }

    # Skip if OD already exists with correct size
    origins_path <- file.path(city_dir, "origins.gpkg")
    destinations_path <- file.path(city_dir, "destinations.gpkg")
    if (file.exists(origins_path) && file.exists(destinations_path)) {
        o_check <- st_read(origins_path, quiet = TRUE)
        if (nrow(o_check) == n_od_pairs) {
            cat(paste("OD matrices for", city, "already exist with correctly sampled", n_od_pairs, "pairs. Skipping...\n"))
            next
        }
    }

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
        slice_sample(n = n_od_pairs, replace = TRUE) |>
        select(volume_m3) |>
        rename(volume = volume_m3) |>
        mutate(id = row_number())

    # Sample destinations (weighted by building volume/area)
    destinations <- buildings_city |>
        filter(!is.na(volume_m3), volume_m3 > 0) |> # filter out NA or non-positive weights to avoid 'negative probability' error
        slice_sample(n = n_od_pairs, weight_by = volume_m3, replace = TRUE) |>
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
