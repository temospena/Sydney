# 10_tidy_up.R
# Tidy up large intermediate routing .rds results by stripping geometries
# but preserving route-level statistics for future analysis.

library(tidyverse)
library(sf)

# Load global configuration
source("code/pipeline/config.R")

cat("Starting Tidy Up Phase (preserving route stats)...\n")

for (city in target_cities) {
  city_lower <- tolower(city)
  city_dir <- file.path(data_dir, city_lower)

  cat("Tidying up", city, "...\n")
  all_stats <- list()

  # Load destinations for backfilling accessibility if missing
  dests_path <- file.path(city_dir, "destinations.gpkg")
  dest_land_use <- NULL
  if (file.exists(dests_path)) {
    cat("  Loading destinations for potential accessibility backfill...\n")
    dest_land_use <- st_read(dests_path, quiet = TRUE) |>
      st_drop_geometry() |>
      select(id, volume) |>
      mutate(id = as.character(id)) |>
      filter(!duplicated(id))
  }

  for (yr in years) {
    for (lts_level in 1:4) {
      res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
      if (file.exists(res_file)) {
        cat("  Extracting stats from:", basename(res_file), "\n")

        # Read the heavy file safely
        trips <- tryCatch(
          readRDS(res_file),
          error = function(e) {
            cat("    [WARN] Failed to read", basename(res_file), "- file may be corrupted. Skipping...\n")
            return(NULL)
          }
        )

        if (is.null(trips)) next

        if (nrow(trips) > 0) {
          # Drop geometries and keep identifiers + Requested metrics

          # detailed_itineraries can return multiple rows per OD pair (segments)
          # We take the first row per OD pair since total_duration/total_distance are route-level constants in r5r output
          stats <- trips |>
            st_drop_geometry() |>
            mutate(from_id = as.character(from_id), to_id = as.character(to_id)) |>
            group_by(from_id, to_id) |>
            summarise(
              total_duration = first(total_duration),
              total_distance = first(total_distance),
              # New route-level enriched columns
              euclidean_distance = first(euclidean_distance),
              route_ci_strong_m = first(route_ci_strong_m),
              route_ci_medium_m = first(route_ci_medium_m),
              route_ci_weak_m = first(route_ci_weak_m),
              route_ci_foot_m = first(route_ci_foot_m),
              route_pct_lts1 = first(route_pct_lts1),
              route_pct_lts2 = first(route_pct_lts2),
              route_pct_lts3 = first(route_pct_lts3),
              route_pct_lts4 = first(route_pct_lts4),
              route_pct_lts1_alternative = if("route_pct_lts1_alternative" %in% names(trips)) first(route_pct_lts1_alternative) else NA,
              route_pct_lts2_alternative = if("route_pct_lts2_alternative" %in% names(trips)) first(route_pct_lts2_alternative) else NA,
              route_pct_lts3_alternative = if("route_pct_lts3_alternative" %in% names(trips)) first(route_pct_lts3_alternative) else NA,
              route_pct_lts4_alternative = if("route_pct_lts4_alternative" %in% names(trips)) first(route_pct_lts4_alternative) else NA,
              route_interruptions_count = first(route_interruptions_count),
              .groups = "drop"
            ) |>
            mutate(year = yr, lts = lts_level)

          # Ensure access_15min_vol is preserved if present
          if ("access_15min_vol" %in% names(trips)) {
            # trips has trip_id as from_id, we need to join the stats
            acc_data <- trips |>
              st_drop_geometry() |>
              group_by(from_id, to_id) |>
              summarise(access_15min_vol = first(access_15min_vol), .groups = "drop")

            stats <- stats |>
              left_join(acc_data, by = c("from_id", "to_id"))
          } else {
            stats$access_15min_vol <- 0
          }

          all_stats[[paste0(yr, "_", lts_level)]] <- stats
        }

        # Preserve heavy file (per user request)
        # file.remove(res_file)
      }
    }
  }

  if (length(all_stats) > 0) {
    df_combined <- bind_rows(all_stats)

    # Save combined long format (smaller rds)
    long_path <- file.path(city_dir, paste0(city_lower, "_routing_stats_all.rds"))
    saveRDS(df_combined, long_path)

    # Save a pivot_wider CSV for easier verification/spreadsheet use
    # Format: dist_16_lts1, dur_16_lts1, etc.
    df_wide <- df_combined |>
      pivot_wider(
        names_from = c(year, lts),
        values_from = c(total_duration, total_distance),
        names_sep = "_v"
      )

    wide_path <- file.path(city_dir, paste0(city_lower, "_routing_stats_wide.csv"))
    write.csv(df_wide, wide_path, row.names = FALSE)

    cat("  Saved compressed stats to:", basename(long_path), "and", basename(wide_path), "\n")
  }
}

cat("Tidy up complete.\n")
