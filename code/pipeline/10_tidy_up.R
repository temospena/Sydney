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

  for (yr in years) {
    for (lts_level in 1:4) {
      res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
      if (file.exists(res_file)) {
        cat("  Extracting stats from:", basename(res_file), "\n")

        # Read the heavy file
        trips <- readRDS(res_file)

        if (nrow(trips) > 0) {
          # Drop geometries and keep identifiers + Requested metrics
          # detailed_itineraries can return multiple rows per OD pair (segments)
          # We take the first row per OD pair since total_duration/total_distance are route-level constants in r5r output
          stats <- trips %>%
            st_drop_geometry() %>%
            group_by(from_id, to_id) %>%
            summarise(
              total_duration = first(total_duration),
              total_distance = first(total_distance),
              .groups = "drop"
            ) %>%
            mutate(year = yr, lts = lts_level)

          all_stats[[paste0(yr, "_", lts_level)]] <- stats
        }

        # Remove heavy file
        file.remove(res_file)
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
    df_wide <- df_combined %>%
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
