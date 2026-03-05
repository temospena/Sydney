# 02_od_data.R
# Generate OD matrices based on building volume weighting and lognormal distance decay
# Uses H3 grid cells to spatially structure origins based on distance from destinations

library(duckdb)
library(sf)
library(dplyr)
library(purrr)
library(h3jsr)
sf_use_s2(FALSE)

# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run

miles_to_meters <- 1609.34

# The city_list.txt is expected to be in the 'data' folder
if (requireNamespace("here", quietly = TRUE)) {
    city_list_path <- here::here("data/city_list.txt")
} else {
    city_list_path <- "data/city_list.txt"
    if (!file.exists(city_list_path)) city_list_path <- "../../data/city_list.txt"
}

# Function to generate 5x5 degree tile names from a bbox
get_tile_names_for_bbox <- function(bbox) {
    # Tiles are 5x5 degrees. Hamburg: e005_n55_e010_n50
    # xmin = floor(lon/5)*5, ymin = floor(lat/5)*5
    lon_min_tile <- floor(bbox["xmin"] / 5) * 5
    lon_max_tile <- floor(bbox["xmax"] / 5) * 5
    lat_min_tile <- floor(bbox["ymin"] / 5) * 5
    lat_max_tile <- floor(bbox["ymax"] / 5) * 5

    lon_vals <- seq(lon_min_tile, lon_max_tile, by = 5)
    lat_vals <- seq(lat_min_tile, lat_max_tile, by = 5)

    tiles <- c()
    for (ln in lon_vals) {
        for (lt in lat_vals) {
            xmin <- ln
            xmax <- ln + 5
            ymin <- lt
            ymax <- lt + 5

            tile <- paste0(
                if (xmin < 0) "w" else "e", sprintf("%03d", abs(xmin)), "_",
                if (ymax < 0) "s" else "n", sprintf("%02d", abs(ymax)), "_",
                if (xmax < 0) "w" else "e", sprintf("%03d", abs(xmax)), "_",
                if (ymin < 0) "s" else "n", sprintf("%02d", abs(ymin))
            )
            tiles <- c(tiles, tile)
        }
    }
    return(unique(tiles))
}

# Function to fetch buildings from S3 parquet using exact bbox, across multiple potential tiles
fetch_building_points <- function(city_name, city_bbox, tile_names) {
    con <- dbConnect(duckdb())
    dbExecute(con, "INSTALL spatial; LOAD spatial; INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2'; SET preserve_insertion_order=false;")

    all_raw_data <- list()

    q_xmin <- city_bbox["xmin"]
    q_ymin <- city_bbox["ymin"]
    q_xmax <- city_bbox["xmax"]
    q_ymax <- city_bbox["ymax"]

    for (tile_name in tile_names) {
        parquet_s3_path <- paste0("s3://us-west-2.opendata.source.coop/tge-labs/globalbuildingatlas-lod1/", tile_name, ".parquet")

        query <- paste0("
        SELECT * EXCLUDE (geometry),
               ST_AsWKB(TRY_CAST(geometry AS GEOMETRY)) as geom_wkb
        FROM read_parquet('", parquet_s3_path, "')
        WHERE bbox.xmin >= ", q_xmin, " AND bbox.xmax <= ", q_xmax, "
          AND bbox.ymin >= ", q_ymin, " AND bbox.ymax <= ", q_ymax)

        message(paste("    Fetching buildings for", city_name, "from tile", tile_name, "..."))

        # Try to fetch, some tiles might not exist
        tile_data <- tryCatch(
            {
                dbGetQuery(con, query)
            },
            error = function(e) {
                # message(paste("      Tile", tile_name, "not found or error. Skipping."))
                return(NULL)
            }
        )

        if (!is.null(tile_data) && nrow(tile_data) > 0) {
            all_raw_data[[tile_name]] <- tile_data |> filter(!is.na(geom_wkb))
        }
    }

    dbDisconnect(con)

    if (length(all_raw_data) == 0) {
        return(NULL)
    }

    raw_data <- bind_rows(all_raw_data) |>
        distinct(id, .keep_all = TRUE) # ensure no duplicates if tiles overlap

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

    # Identify all tiles to fetch: those matching the city name AND those overlapping the bbox
    matches <- city_list_all |> filter(city == !!city)
    calc_tiles <- get_tile_names_for_bbox(bbox)

    target_tiles_fetch <- unique(c(matches$tile_name, calc_tiles))
    target_tiles_fetch <- target_tiles_fetch[!is.na(target_tiles_fetch) & target_tiles_fetch != ""]

    if (length(target_tiles_fetch) == 0) {
        warning(paste("No tile mapping found for", city))
        next
    }

    # Skip if OD already exists with correct size
    origins_path <- file.path(city_dir, "origins.gpkg")
    destinations_path <- file.path(city_dir, "destinations.gpkg")
    if (file.exists(origins_path) && file.exists(destinations_path) && !FORCE_RERUN) {
        o_check <- st_read(origins_path, quiet = TRUE)
        if (nrow(o_check) == n_od_pairs) {
            cat(paste("OD matrices for", city, "already exist with", n_od_pairs, "pairs. Skipping...\n"))
            next
        }
    }

    cat("Fetching buildings...\n")
    buildings <- fetch_building_points(city, bbox, target_tiles_fetch)

    if (is.null(buildings) || nrow(buildings) == 0) {
        warning(paste("No buildings fetched for", city))
        next
    }

    cat("Processing buildings to H3 grid...\n")
    # Filter precisely to the 10km polygon
    buildings_city <- buildings[city_poly, ]
    rm(buildings)
    gc()

    # 1. Map buildings to H3 cells
    buildings_city <- buildings_city |>
        mutate(h3_addr = point_to_cell(geometry, res = h3_res)) |>
        filter(volume_m3 > 0) # ensure volume is > 0 for weighting

    # We only sample in grids WITH buildings
    valid_h3_pool <- unique(buildings_city$h3_addr)

    # 1.5 Generate full land use dataset for accessibility (all cells in 10km buffer)
    cat("Generating full land use dataset for accessibility...\n")
    land_use_h3 <- buildings_city |>
        st_drop_geometry() |>
        group_by(h3_addr) |>
        summarise(volume = sum(volume_m3, na.rm = TRUE), .groups = "drop") |>
        filter(volume > 0)

    # Cast H3 addresses to polygons and append volume
    land_use_sf <- h3jsr::cell_to_polygon(land_use_h3$h3_addr, simple = FALSE) |>
        mutate(
            id = land_use_h3$h3_addr,
            volume = land_use_h3$volume
        ) |>
        select(id, volume, geometry)

    land_use_path <- file.path(city_dir, "land_use.gpkg")
    st_write(land_use_sf, land_use_path, delete_dsn = TRUE, quiet = TRUE)


    cat("Sampling destinations and generating origin targets...\n")
    # 2. Sample DESTINATION buildings weighted by volume (building-level sampling)
    dest_samples <- buildings_city |>
        slice_sample(n = n_od_pairs, weight_by = volume_m3, replace = TRUE) |>
        st_drop_geometry() |>
        mutate(
            trip_id = row_number(),
            target_dist_m = rlnorm(n(), meanlog = mu_log, sdlog = sd_log) * miles_to_meters
        )

    # 3. Find ORIGIN H3 cells based on target distance from Destination H3 cell
    # An H3 Res 9 edge length is ~174m, diameter is ~400m
    avg_spacing <- 400

    find_origin <- function(dest_h3, target_m, pool) {
        ring_radius <- ceiling(target_m / avg_spacing)
        potential_cells <- get_ring(dest_h3, ring_radius) |> unlist()
        candidates <- pool[pool %in% potential_cells]

        if (length(candidates) == 0) {
            # Fallback to a random cell if none exist at exact ring
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
        mutate(
            id = dest_samples$trip_id, trip_id = dest_samples$trip_id, type = "destination",
            volume = dest_samples$volume_m3
        )

    orig_sf <- h3jsr::cell_to_polygon(dest_samples$orig_h3, simple = FALSE) |>
        st_centroid() |>
        mutate(
            id = dest_samples$trip_id, trip_id = dest_samples$trip_id, type = "origin",
            volume = 1L
        ) # unweighted origins

    # Save lightweight files (same filenames as v1 for pipeline compatibility)
    st_write(orig_sf, origins_path, append = FALSE, delete_dsn = TRUE, quiet = TRUE)
    st_write(dest_sf, destinations_path, append = FALSE, delete_dsn = TRUE, quiet = TRUE)

    cat(paste("Successfully generated OD matrices for", city, "(v2 lognormal distance decay)\n"))
}
