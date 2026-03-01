# test_od_sampling_lisbon.R
# Test script to sample OD matrices based on building volumes and H3 grids
# and generate plots for distance and OD distributions.

library(duckdb)
library(sf)
library(dplyr)
library(purrr)
library(h3jsr)
library(ggplot2)
library(patchwork)
sf_use_s2(FALSE)

# Load global configuration
source("code/pipeline/config.R")
city_to_run <- "Lisbon"
n_od_pairs <- 20000

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

city <- city_to_run
city_lower <- tolower(city)
city_dir <- file.path(data_dir, city_lower)
city_poly_path <- file.path(city_dir, paste0(city_lower, "_10km.gpkg"))

results_dir <- file.path(city_dir, "results")
if (!dir.exists(results_dir)) {
    dir.create(results_dir, recursive = TRUE)
}

if (!file.exists(city_poly_path)) {
    stop(paste("Missing poly for", city))
}

city_poly <- st_read(city_poly_path, quiet = TRUE)
bbox <- st_bbox(city_poly)

city_list_all <- read.csv(city_list_path, header = FALSE) |>
    rename(city = V1, lat = V2, lon = V3, tile_name = V7)

matches <- city_list_all |> filter(tolower(city) == tolower(!!city))

if (nrow(matches) == 0) {
    stop(paste("No tile mapping found in city_list.txt for", city))
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
    stop(paste("Invalid tile name found in city_list.txt for", city))
}

cat("Fetching buildings...\n")
buildings <- fetch_building_points(city, bbox, tile_name)

if (is.null(buildings) || nrow(buildings) == 0) {
    stop(paste("No buildings fetched for", city))
}

cat("Processing buildings to H3 grid...\n")
# Filter precisely to the 10km polygon
buildings_city <- buildings[city_poly, ]
rm(buildings)
gc()

# 1. Map buildings to H3 cells FIRST
buildings_city <- buildings_city |>
    mutate(h3_addr = point_to_cell(geometry, res = h3_res)) |>
    filter(volume_m3 > 0) # ensure volume is > 0 for weighting

# We only sample in the grids WITH buildings
valid_h3_pool <- unique(buildings_city$h3_addr)

cat("Sampling destinations and generating origin targets...\n")
# 2. Sample DESTINATION buildings weighted by volume
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

cat("Generating O/D SF centroids...\n")
# Convert h3 cells to polygons, then to centroids
dest_sf <- h3jsr::cell_to_polygon(dest_samples$h3_addr, simple = FALSE) |>
    st_centroid() |>
    mutate(id = dest_samples$trip_id, trip_id = dest_samples$trip_id, type = "destination")

orig_sf <- h3jsr::cell_to_polygon(dest_samples$orig_h3, simple = FALSE) |>
    st_centroid() |>
    mutate(id = dest_samples$trip_id, trip_id = dest_samples$trip_id, type = "origin")


# Calculate linear distance to verify distributions
dist_m <- as.numeric(st_distance(orig_sf, dest_sf, by_element = TRUE))

df_plot <- data.frame(
    distance_m = dist_m
)

cat("Generating Plots...\n")
# Plot 1: Cumulative Distance Density Curve
p_cdf <- ggplot(df_plot, aes(x = distance_m)) +
    stat_ecdf(geom = "step", color = "blue", size = 1) +
    labs(
        title = paste("Cumulative Distance Distribution Operations (n =", n_od_pairs, ")"),
        x = "Linear Distance (meters)",
        y = "Cumulative Probability"
    ) +
    theme_minimal() +
    coord_cartesian(xlim = c(0, quantile(df_plot$distance_m, 0.99)))

ggsave(file.path(results_dir, "test_od_cdf.png"), plot = p_cdf, width = 8, height = 6, dpi = 300)

# Prepare hexbins
orig_counts <- dest_samples |> count(orig_h3, name = "n_origins")
dest_counts <- dest_samples |> count(h3_addr, name = "n_destinations")

orig_hex <- h3jsr::cell_to_polygon(orig_counts$orig_h3, simple = FALSE) |>
    st_as_sf() |>
    mutate(n_origins = orig_counts$n_origins)

dest_hex <- h3jsr::cell_to_polygon(dest_counts$h3_addr, simple = FALSE) |>
    st_as_sf() |>
    mutate(n_destinations = dest_counts$n_destinations)

# Plot 2: Hexbin Map of Origins
p_orig <- ggplot() +
    geom_sf(data = city_poly, fill = "gray95", color = "black", linewidth = 0.5) +
    geom_sf(data = orig_hex, aes(fill = n_origins), color = NA) +
    scale_fill_viridis_c(option = "magma", trans = "log1p", guide = guide_colorbar(title = "Origins")) +
    labs(title = "Origin H3 Cells Distribution") +
    theme_void() +
    theme(legend.position = "bottom")

# Plot 3: Hexbin Map of Destinations
p_dest <- ggplot() +
    geom_sf(data = city_poly, fill = "gray95", color = "black", linewidth = 0.5) +
    geom_sf(data = dest_hex, aes(fill = n_destinations), color = NA) +
    scale_fill_viridis_c(option = "viridis", trans = "log1p", guide = guide_colorbar(title = "Destinations")) +
    labs(title = "Destination H3 Cells Distribution") +
    theme_void() +
    theme(legend.position = "bottom")

p_maps <- p_orig | p_dest
ggsave(file.path(results_dir, "test_od_hexbins.png"), plot = p_maps, width = 12, height = 6, dpi = 300)

cat(paste("Successfully generated test results in", results_dir, "\n"))
