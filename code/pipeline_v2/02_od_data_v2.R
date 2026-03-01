# 02_od_data_v2.R
# Generate OD matrices based on H3 grid cells and a lognormal distance decay function

library(duckdb)
library(sf)
library(dplyr)
library(purrr)
library(h3jsr)
sf_use_s2(FALSE)

# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run

h3_res <- 9
mu_log <- 0.33
sd_log <- 0.66
miles_to_meters <- 1609.34

if (requireNamespace("here", quietly = TRUE)) {
    city_list_path <- here::here("data/city_list.txt")
} else {
    city_list_path <- "data/city_list.txt"
    if (!file.exists(city_list_path)) city_list_path <- "../../data/city_list.txt"
}

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

set.seed(42) # for reproducibility

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

    city_list_all <- read.csv(city_list_path, header = FALSE) |>
        rename(city = V1, lat = V2, lon = V3, tile_name = V7)

    matches <- city_list_all |> filter(city == !!city)

    if (nrow(matches) == 0) {
        warning(paste("No tile mapping found in city_list.txt for", city))
        next
    }

    if (nrow(matches) > 1) {
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

    origins_path <- file.path(city_dir, "origins_v2.gpkg")
    destinations_path <- file.path(city_dir, "destinations_v2.gpkg")
    if (file.exists(origins_path) && file.exists(destinations_path) && !FORCE_RERUN) {
        o_check <- st_read(origins_path, quiet = TRUE)
        if (nrow(o_check) == n_od_pairs) {
            cat(paste("OD matrices for", city, "already exist. Skipping...\n"))
            next
        }
    }

    cat("Fetching buildings...\n")
    buildings <- fetch_building_points(city, bbox, tile_name)

    if (is.null(buildings) || nrow(buildings) == 0) {
        warning(paste("No buildings fetched for", city))
        next
    }

    cat("Processing buildings to H3 grid...\n")
    # Filter precisely to the 10km polygon
    buildings_city <- buildings[city_poly, ]
    rm(buildings)
    gc()

    # Map buildings to H3 cells
    buildings_city <- buildings_city |>
        mutate(h3_addr = point_to_cell(geometry, res = h3_res))

    # Group by H3 cell and calculate total volume
    h3_cells <- buildings_city |>
        st_drop_geometry() |>
        group_by(h3_addr) |>
        summarise(volume = sum(volume_m3, na.rm = TRUE), n_buildings = n()) |>
        filter(volume > 0)

    cat("Sampling destinations and generating origin targets...\n")
    # 1. Sample destinations weighted by volume
    dest_samples <- h3_cells |>
        slice_sample(n = n_od_pairs, weight_by = volume, replace = TRUE) |>
        mutate(
            trip_id = row_number(),
            target_dist_m = rlnorm(n(), meanlog = mu_log, sdlog = sd_log) * miles_to_meters
        )

    # 2. Find origins based on target distance
    valid_h3_pool <- h3_cells$h3_addr
    # An H3 Res 9 edge length is ~174m, diameter is ~400m
    avg_spacing <- 400

    find_origin <- function(dest_h3, target_m, pool) {
        ring_radius <- ceiling(target_m / avg_spacing)
        potential_cells <- get_ring(dest_h3, ring_radius) |> unlist()
        candidates <- pool[pool %in% potential_cells]

        if (length(candidates) == 0) {
            # Fallback
            return(sample(pool, 1))
        }
        sample(candidates, 1)
    }

    origins_h3 <- map2_chr(dest_samples$h3_addr, dest_samples$target_dist_m, ~ find_origin(.x, .y, valid_h3_pool))
    dest_samples$orig_h3 <- origins_h3

    cat("Generating SF centroids and saving...\n")
    # Convert h3 cells to polygons, then to centroids
    dest_sf <- h3jsr::cell_to_polygon(dest_samples$h3_addr, simple = FALSE) |>
        st_centroid() |>
        mutate(id = dest_samples$trip_id, trip_id = dest_samples$trip_id, type = "destination")

    orig_sf <- h3jsr::cell_to_polygon(dest_samples$orig_h3, simple = FALSE) |>
        st_centroid() |>
        mutate(id = dest_samples$trip_id, trip_id = dest_samples$trip_id, type = "origin")

    # Save lightweight files
    st_write(orig_sf, origins_path, append = FALSE, delete_dsn = TRUE, quiet = TRUE)
    st_write(dest_sf, destinations_path, append = FALSE, delete_dsn = TRUE, quiet = TRUE)

    cat(paste("Successfully generated OD matrices for", city, "(V2)\n"))
}
