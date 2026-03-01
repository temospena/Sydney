# 01_valhalla_routing_2026.R
# Test routing 20k OD pairs query using local Valhalla graph for 2026

library(sf)
library(dplyr)
library(httr)
library(jsonlite)
library(parallel)
library(stplanr)
library(ggplot2)
sf_use_s2(FALSE)

source("code/pipeline/config.R")
data_dir <- file.path(getwd(), "data/pipeline")

city <- "Lisbon"
city_lower <- tolower(city)
city_dir <- file.path(data_dir, city_lower)
results_dir <- file.path(city_dir, "results")
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

orig_path <- file.path(city_dir, "origins_v2.gpkg")
dest_path <- file.path(city_dir, "destinations_v2.gpkg")

cat("Loading 20,000 OD Pairs...\n")
orig <- st_read(orig_path, quiet = TRUE)
dest <- st_read(dest_path, quiet = TRUE)

od_pairs <- data.frame(
    trip_id = orig$trip_id,
    o_lon = st_coordinates(orig)[, 1],
    o_lat = st_coordinates(orig)[, 2],
    d_lon = st_coordinates(dest)[, 1],
    d_lat = st_coordinates(dest)[, 2]
) |>
    distinct(o_lon, o_lat, d_lon, d_lat, .keep_all = TRUE)

# Test single batch of queries
route_one_valhalla <- function(i) {
    # Construct Valhalla JSON payload for /route endpoint
    o_lat <- od_pairs$o_lat[i]
    o_lon <- od_pairs$o_lon[i]
    d_lat <- od_pairs$d_lat[i]
    d_lon <- od_pairs$d_lon[i]

    # We specify "bicycle" costing profile to mimic standard CI
    req_json <- paste0(
        '{"locations":[{"lat":', o_lat, ',"lon":', o_lon, '},{"lat":', d_lat, ',"lon":', d_lon, '}],"costing":"bicycle","directions_options":{"units":"kilometers"},"format":"osrm"}'
    )

    url <- "http://localhost:8002/route"

    res <- tryCatch(POST(url, body = req_json, timeout(15)), error = function(e) NULL)

    if (!is.null(res) && status_code(res) == 200) {
        # Valhalla returns standard OSRM format payload if we specify format=osrm
        content_txt <- content(res, as = "text", encoding = "UTF-8")
        parsed <- tryCatch(fromJSON(content_txt), error = function(e) NULL)

        if (!is.null(parsed) && length(parsed$routes) > 0) {
            # Extract standard straightline and distance params
            route <- parsed$routes[1, ]
            dist_m <- as.numeric(route$distance)
            dur_s <- as.numeric(route$duration)

            # Polyline geometry parsing
            # Valhalla natively returns precision 6 polyline, not standard 5 like typical OSRM
            # So a quick call directly to curl using simple route endpoint returns a proper route
        }
    }
}
