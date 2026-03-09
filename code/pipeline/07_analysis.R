# 06_analysis.R
# Analyze routing results: distances, circuity, and visualizations

library(tidyverse)
library(sf)
library(stplanr)
library(tmap)
library(ggplot2)

# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run

cat("Starting Phase 3 Analysis...\n")

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)
    results_dir <- file.path(city_dir, "results")
    dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

    cat(paste("Processing analysis for", city, "\n"))

    # Process analysis for LTS 1 to 4
    for (lts_level in lts_levels) {
        cat(paste("  Analyzing LTS", lts_level, "\n"))

        trips_list <- list()
        for (yr in years) {
            res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
            res_file_long <- file.path(city_dir, paste0("trips_", city_lower, "_20", yr, "_lts", lts_level, ".rds"))

            trips_to_read <- NULL
            if (file.exists(res_file)) {
                trips_to_read <- res_file
            } else if (file.exists(res_file_long)) {
                trips_to_read <- res_file_long
            }

            if (!is.null(trips_to_read)) {
                loaded_trips <- tryCatch(
                    readRDS(trips_to_read),
                    error = function(e) {
                        cat("    [WARN] Failed to read", basename(trips_to_read), "- file may be corrupted. Skipping...\n")
                        return(NULL)
                    }
                )
                if (!is.null(loaded_trips)) {
                    trips_list[[yr]] <- loaded_trips |> mutate(year = paste0("20", yr))
                }
            } else {
                cat("    [MISSING] No results found for Year", yr, "(LTS", lts_level, ")\n")
            }
        }

        if (length(trips_list) < 2) {
            cat("    Not enough years available to run comparisons. Skipping...\n")
            next
        }

        # Combine all
        trips_combined <- do.call(rbind, trips_list) |>
            mutate(year = as.factor(year)) |>
            st_as_sf()
        if (inherits(trips_combined, "sf")) st_geometry(trips_combined) <- "geometry"

        # Calculate snapped linear distance and circuity directly from routing geometries
        cat("    Calculating linear snapped distances and circuity...\n")
        trips_combined <- trips_combined |>
            mutate(
                snapped_start = lwgeom::st_startpoint(geometry),
                snapped_end = lwgeom::st_endpoint(geometry),
                linear_distance = as.numeric(st_distance(snapped_start, snapped_end, by_element = TRUE)),
                circuity = total_distance / pmax(linear_distance, 1)
            ) |>
            select(-snapped_start, -snapped_end)

        trips_df <- trips_combined |> st_drop_geometry()

        # Discard OD pairs missing in at least one year
        n_years <- length(unique(trips_df$year))
        valid_ods <- trips_df |>
            count(from_id, to_id) |>
            filter(n == n_years)

        trips_df <- trips_df |> inner_join(valid_ods |> select(from_id, to_id), by = c("from_id", "to_id"))
        cat("    Filtered to", nrow(valid_ods), "OD pairs successfully routed across all years.\n")

        # Prepare distance comparisons table
        trips_wide <- trips_df |>
            select(from_id, to_id, total_distance, year) |>
            pivot_wider(values_from = total_distance, names_from = year, names_prefix = "dist_")

        available_years <- sort(unique(trips_df$year))

        # Dynamic distance change processing
        first_yr <- available_years[1]
        last_yr <- available_years[length(available_years)]
        first_col <- paste0("dist_", first_yr)
        last_col <- paste0("dist_", last_yr)

        if (first_col %in% names(trips_wide) && last_col %in% names(trips_wide)) {
            trips_wide <- trips_wide |>
                mutate(
                    change_pct = (.data[[last_col]] - .data[[first_col]]) / .data[[first_col]]
                )
        }
        write.csv(trips_wide, file.path(results_dir, paste0("routing_differences_lts", lts_level, ".csv")), row.names = FALSE)

        # Aggressive memory cleanup for this LTS level
        rm(trips_list, trips_combined, trips_df, trips_wide)
        gc()
    }
}

cat("Analysis Phase Complete. All metrics and plots saved.\n")
