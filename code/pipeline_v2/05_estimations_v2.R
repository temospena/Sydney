# 05_estimations_v2.R
# Estimate CI percentages and overall metrics for BRouter results

library(sf)
library(dplyr)
library(tidyr)
sf_use_s2(FALSE)

# Load v2 configuration (server/local flag, target cities, paths, etc.)
source("code/pipeline_v2/config_v2.R")

YEARS <- names(BROUTER_PORTS) # c("16", "21", "26")
V_YEARS <- c("2016", "2021", "2026")

out_csv <- file.path(data_dir, "final_city_estimations_v2.csv")

final_dataset <- list()

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)

    orig_path <- file.path(city_dir, "origins_v2.gpkg")
    dest_path <- file.path(city_dir, "destinations_v2.gpkg")

    if (!file.exists(orig_path) || !file.exists(dest_path)) {
        warning(paste("Missing OD matrices for", city, "- skipping."))
        next
    }

    origins <- st_read(orig_path, quiet = TRUE)
    dest <- st_read(dest_path, quiet = TRUE)

    orig_coords <- st_coordinates(origins)
    dest_coords <- st_coordinates(dest)

    od_pairs_lookup <- data.frame(
        trip_id = origins$trip_id,
        linear_distance = sqrt(
            ((dest_coords[, 1] - orig_coords[, 1]) * 111320 * cos(orig_coords[, 2] * pi / 180))^2 +
                ((dest_coords[, 2] - orig_coords[, 2]) * 111320)^2
        )
    )

    for (i in seq_along(YEARS)) {
        yr <- YEARS[i]
        v_ext <- versions[which(years == yr)]

        routes_path <- file.path(city_dir, paste0("routes_v2_", yr, ".gpkg"))
        if (!file.exists(routes_path)) {
            cat(paste("Routes file missing for", city, yr, "Skipping...\n"))
            next
        }

        ci_path <- file.path(city_dir, paste0(city_lower, "_ci_osmactive_", v_ext, ".gpkg"))
        ci <- NULL
        if (file.exists(ci_path)) {
            ci <- st_read(ci_path, quiet = TRUE)
        }

        routes <- st_read(routes_path, quiet = TRUE)

        if (nrow(routes) == 0) {
            cat(paste("No routes processed for", city, yr, "Skipping...\n"))
            next
        }

        start_time <- Sys.time()

        # Calculate geometric lengths in meters
        routes <- routes |> st_transform(3857)
        routes$geom_length <- as.numeric(st_length(routes))

        # We also have total-time and track-length provided by BRouter geojson properties if needed.
        # Usually properties are `track-length` and `total-time`
        if ("track.length" %in% names(routes)) {
            routes$brouter_dist <- routes$track.length
        } else if ("track_length" %in% names(routes)) {
            routes$brouter_dist <- as.numeric(routes$track_length)
        } else {
            routes$brouter_dist <- routes$geom_length
        }

        if ("total.time" %in% names(routes)) {
            routes$duration_min <- as.numeric(routes$total.time) / 60
        } else if ("total_time" %in% names(routes)) {
            routes$duration_min <- as.numeric(routes$total_time) / 60
        } else {
            routes$duration_min <- NA
        }

        routes <- routes |>
            left_join(od_pairs_lookup, by = "trip_id") |>
            mutate(circuity = brouter_dist / pmax(linear_distance, 1))

        avg_dist <- mean(routes$brouter_dist, na.rm = TRUE)
        avg_circ <- mean(routes$circuity, na.rm = TRUE)
        avg_dur <- mean(routes$duration_min, na.rm = TRUE)
        found <- nrow(routes)

        pct_ci_route_type_strong_ci <- 0
        pct_ci_route_type_moderate_ci <- 0
        pct_ci_route_type_weak_ci <- 0
        pct_ci_route_type_shared_foot <- 0
        pct_ci_route <- 0

        if (!is.null(ci) && nrow(ci) > 0) {
            cat(paste("  Calculating CI route spatial intersections for", city, yr, "...\n"))
            ci <- ci |> st_transform(3857)

            # Prepare CI types
            # We buffer CI by 15 meters to catch slight routing misalignments
            ci_buffered <- st_buffer(st_geometry(ci), 15)
            ci_buffered_sf <- st_sf(infra5 = ci$cycle_cat, geometry = ci_buffered)

            # Intersect routes with CI buffer
            # This computes the pieces of each route that fall inside each infrastructure buffer
            intersections <- st_intersection(routes |> select(trip_id, geom_length), ci_buffered_sf)

            if (nrow(intersections) > 0) {
                intersections$intersect_len <- as.numeric(st_length(intersections))

                # Aggregate by trip and CI type
                ci_stats <- intersections |>
                    st_drop_geometry() |>
                    group_by(trip_id, infra5) |>
                    summarise(len = sum(intersect_len, na.rm = TRUE), .groups = "drop")

                # Merge back to total routes to calculate percentages
                routes_ci <- routes |>
                    st_drop_geometry() |>
                    select(trip_id, geom_length) |>
                    left_join(ci_stats, by = "trip_id") |>
                    mutate(len = replace_na(len, 0))

                # Overall CI per route percentage
                sum_ci_per_route <- routes_ci |>
                    group_by(trip_id) |>
                    summarise(total_ci_len = sum(len, na.rm = TRUE), geom_length = first(geom_length), .groups = "drop") |>
                    mutate(pct = total_ci_len / pmax(geom_length, 1))

                pct_ci_route <- mean(sum_ci_per_route$pct, na.rm = TRUE) * 100

                # Individual CI types
                calc_type_pct <- function(type_name) {
                    type_data <- routes_ci |> filter(infra5 == type_name)
                    if (nrow(type_data) == 0) {
                        return(0)
                    }

                    # Compute percentage per route, then average over all found routes
                    # Needs to account for routes that have 0 length of this type
                    full_type <- routes |>
                        st_drop_geometry() |>
                        select(trip_id, geom_length) |>
                        left_join(type_data |> select(trip_id, len), by = "trip_id") |>
                        mutate(
                            len = replace_na(len, 0),
                            pct = len / pmax(geom_length, 1)
                        )
                    return(mean(full_type$pct, na.rm = TRUE) * 100)
                }

                pct_ci_route_type_strong_ci <- calc_type_pct("strong_ci")
                pct_ci_route_type_moderate_ci <- calc_type_pct("moderate_ci")
                pct_ci_route_type_weak_ci <- calc_type_pct("weak_ci")
                pct_ci_route_type_shared_foot <- calc_type_pct("shared_foot")
            }
        }

        end_time <- Sys.time()
        proc_time <- as.numeric(difftime(end_time, start_time, units = "mins"))

        row_data <- data.frame(
            city = city,
            year = V_YEARS[i],
            run_timestamp = format(Sys.time(), "%Y%m%d_%H%M%S"),
            avg_distance_m = round(avg_dist, 2),
            avg_circuity = round(avg_circ, 2),
            avg_dist_change_pct = NA, # Calculated later across years
            pct_ci_route = round(pct_ci_route, 2),
            pct_ci_route_type_strong_ci = round(pct_ci_route_type_strong_ci, 2),
            pct_ci_route_type_moderate_ci = round(pct_ci_route_type_moderate_ci, 2),
            pct_ci_route_type_weak_ci = round(pct_ci_route_type_weak_ci, 2),
            pct_ci_route_type_shared_foot = round(pct_ci_route_type_shared_foot, 2),
            avg_duration_min = round(avg_dur, 2),
            access_15min_vol = NA, # Access not calculated in V2 yet
            found_routes = found,
            processing_time_minutes = round(proc_time, 2)
        )

        final_dataset[[length(final_dataset) + 1]] <- row_data
    }
}

if (length(final_dataset) > 0) {
    final_df <- bind_rows(final_dataset) |>
        group_by(city) |>
        arrange(year) |>
        mutate(
            baseline_dist = first(avg_distance_m[year == "2016"]),
            avg_dist_change_pct = round((avg_distance_m - baseline_dist) / pmax(baseline_dist, 1) * 100, 2)
        ) |>
        select(-baseline_dist) |>
        ungroup()

    if (file.exists(out_csv)) {
        existing_df <- read.csv(out_csv) |> mutate(year = as.character(year))
        new_keys <- final_df |>
            mutate(k = paste(city, year)) |>
            pull(k)
        existing_df <- existing_df |>
            mutate(k = paste(city, year)) |>
            filter(!(k %in% new_keys)) |>
            select(-k)
        final_df <- bind_rows(existing_df, final_df)
    }

    final_df <- final_df |> arrange(city, year)
    write.csv(final_df, out_csv, row.names = FALSE)
    cat("Dataset saved to:", out_csv, "\n")
} else {
    cat("No data generated.\n")
}
