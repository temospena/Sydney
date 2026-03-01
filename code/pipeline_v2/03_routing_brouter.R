# 03_routing_brouter.R
# Query local BRouter instances for historical paths
# Note: Requires docker-compose to be running (docker compose up -d)

library(sf)
library(dplyr)
library(purrr)
library(httr)
library(parallel)

sf_use_s2(FALSE)

# Load v2 configuration (server/local flag, ports, target cities, n_od_pairs)
source("code/pipeline_v2/config_v2.R")

YEARS <- names(BROUTER_PORTS) # c("16", "21", "26")
V_YEARS <- c("2016", "2021", "2026")

# port_map is BROUTER_PORTS from config_v2.R
port_map <- BROUTER_PORTS

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)

    orig_path <- file.path(city_dir, "origins_v2.gpkg")
    dest_path <- file.path(city_dir, "destinations_v2.gpkg")

    if (!file.exists(orig_path) || !file.exists(dest_path)) {
        warning(paste("Missing OD files for", city, "Skipping..."))
        next
    }

    orig <- st_read(orig_path, quiet = TRUE)
    dest <- st_read(dest_path, quiet = TRUE)

    orig_coords <- st_coordinates(orig)
    dest_coords <- st_coordinates(dest)

    # Join them by ID assuming order or explicit ID match
    od_pairs <- orig |>
        st_drop_geometry() |>
        select(trip_id) |>
        mutate(
            o_lon = orig_coords[, 1],
            o_lat = orig_coords[, 2]
        ) |>
        left_join(
            dest |> st_drop_geometry() |> select(trip_id) |> mutate(d_lon = dest_coords[, 1], d_lat = dest_coords[, 2]),
            by = "trip_id"
        )

    unique_pairs <- od_pairs |>
        distinct(o_lon, o_lat, d_lon, d_lat) |>
        mutate(pair_id = row_number())

    od_pairs <- od_pairs |> left_join(unique_pairs, by = c("o_lon", "o_lat", "d_lon", "d_lat"))

    for (yr in YEARS) {
        port <- port_map[yr]
        out_path <- file.path(city_dir, paste0("routes_v2_", yr, ".gpkg"))

        if (file.exists(out_path) && !FORCE_RERUN) {
            cat(paste("Routes for", city, yr, "already exist. Skipping...\n"))
            next
        }

        cat(paste("Routing for", city, "year", yr, "on port", port, "...\n"))

        # Check if BRouter instance is alive
        test_url <- paste0(
            "http://localhost:", port, "/brouter?lonlats=",
            od_pairs$o_lon[1], ",", od_pairs$o_lat[1], "|",
            od_pairs$d_lon[1], ",", od_pairs$d_lat[1],
            "&profile=cycling_ci&alternativeidx=0&format=geojson"
        )

        test_res <- tryCatch(GET(test_url, timeout(10)), error = function(e) NULL)
        if (is.null(test_res) || status_code(test_res) != 200) {
            warning(paste("BRouter instance not reachable or returned error at", test_url, "Skipping..."))
            next
        }

        route_one <- function(i) {
            o_lon <- unique_pairs$o_lon[i]
            o_lat <- unique_pairs$o_lat[i]
            d_lon <- unique_pairs$d_lon[i]
            d_lat <- unique_pairs$d_lat[i]
            pid <- unique_pairs$pair_id[i]

            url <- paste0(
                "http://localhost:", port, "/brouter?lonlats=",
                o_lon, ",", o_lat, "|", d_lon, ",", d_lat,
                "&profile=cycling_ci&alternativeidx=0&format=geojson"
            )

            res <- tryCatch(GET(url, timeout(30)), error = function(e) NULL)

            if (!is.null(res) && status_code(res) == 200) {
                content <- content(res, as = "text", encoding = "UTF-8")
                geojson_sf <- tryCatch(st_read(content, quiet = TRUE), error = function(e) NULL)

                if (!is.null(geojson_sf) && nrow(geojson_sf) > 0) {
                    # Extract features and remove list columns like messages and times
                    props <- geojson_sf[1, ]

                    # Convert list columns to null to prevent st_write crashes
                    list_cols <- sapply(props, is.list)
                    # Keep geometry column as list since sf needs it
                    list_cols[names(list_cols) == attr(props, "sf_column")] <- FALSE

                    for (col in names(list_cols)[list_cols]) {
                        props[[col]] <- NULL
                    }

                    # Convert GeoJSON metadata character fields to integers
                    if ("track.length" %in% names(props)) props$track.length <- as.numeric(props$track.length)
                    if ("total.time" %in% names(props)) props$total.time <- as.numeric(props$total.time)
                    if ("cost" %in% names(props)) props$cost <- as.numeric(props$cost)

                    # Discard routes with unrealistic duration (> 120 min = 7200 sec)
                    max_sec <- 120 * 60
                    if (!is.na(props$total.time) && props$total.time > max_sec) {
                        return(NULL)
                    }

                    props$pair_id <- pid
                    return(props)
                }
            }
            return(NULL)
        }

        # Execute routing in parallel
        results <- mclapply(seq_len(nrow(unique_pairs)), route_one, mc.cores = detectCores() - 1)

        valid_results <- compact(results)

        if (length(valid_results) > 0) {
            unique_routes <- dplyr::bind_rows(valid_results)
            unique_routes_sf <- st_as_sf(unique_routes)
            if (st_crs(unique_routes_sf)$epsg != 4326) st_crs(unique_routes_sf) <- 4326

            # Join back the duplicated pairs retaining properties
            all_routes <- unique_routes_sf |>
                inner_join(od_pairs |> select(trip_id, pair_id), by = "pair_id", relationship = "one-to-many") |>
                select(-pair_id) |>
                relocate(trip_id)

            all_routes <- st_as_sf(all_routes)

            st_write(all_routes, out_path, append = FALSE, quiet = TRUE, delete_dsn = TRUE)
            cat(paste("  Saved", nrow(all_routes), "routes to", out_path, "using", nrow(unique_routes_sf), "unique API requests\n"))
        } else {
            warning(paste("No valid routes found for", city, yr))
        }
    }
}
