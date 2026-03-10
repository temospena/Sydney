# 12_add_lts_alternative.R
# Standalone script to add route_pct_ltsX_alternative to already processed city routing_stats_all.rds

library(tidyverse)
library(sf)
library(ggplot2)

# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run

cat("Starting LTS Alternative Metric Extraction...\n")

for (city in target_cities) {
  city_lower <- tolower(city)
  city_dir <- file.path(data_dir, city_lower)

  cat("Processing", city, "...\n")
  all_stats <- list()

  for (yr in years) {
    # Load CI layer for this year to act as "ci_custom" (forcing LTS=1)
    v_ext <- versions[which(years == yr)]
    ci_path <- file.path(city_dir, paste0(city_lower, "_ci_osmactive_", v_ext, ".gpkg"))

    ci_osm_ids <- c()
    if (file.exists(ci_path)) {
      ci <- st_read(ci_path, quiet = TRUE)
      if ("osm_id" %in% names(ci)) {
        ci_osm_ids <- ci$osm_id
      }
      rm(ci)
    }

    # Load LTS edges
    r5r_dir <- file.path(city_dir, paste0("r5r_", yr))
    edges_path <- file.path(r5r_dir, paste0(city_lower, "_", yr, "_lts.gpkg"))

    edges <- NULL
    if (file.exists(edges_path)) {
      edges <- st_read(edges_path, quiet = TRUE) |>
        st_drop_geometry() |>
        select(edge_index, osm_id, bicycle_lts, length)
    }

    for (lts_level in lts_levels) {
      res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
      res_file_long <- file.path(city_dir, paste0("trips_", city_lower, "_20", yr, "_lts", lts_level, ".rds"))

      trips_to_read <- NULL
      if (file.exists(res_file)) {
        trips_to_read <- res_file
      } else if (file.exists(res_file_long)) {
        trips_to_read <- res_file_long
      }

      if (!is.null(trips_to_read)) {
        cat("  Extracting alternative metrics from:", basename(trips_to_read), "\n")

        trips <- readRDS(trips_to_read)
        if (nrow(trips) > 0 && !is.null(edges)) {
          # We only need one row per OD to get the edge list
          target_for_metrics <- trips |>
            mutate(from_id = as.character(from_id), to_id = as.character(to_id)) |>
            group_by(from_id, to_id) |>
            slice(1) |>
            ungroup()

          if ("edge_id_list" %in% names(target_for_metrics)) {
            edge_list_str <- as.character(target_for_metrics$edge_id_list)
            edge_list <- strsplit(edge_list_str, ",")

            route_edges_mapping <- data.frame(
              row_idx = rep(1:nrow(target_for_metrics), lengths(edge_list)),
              edge_index = as.numeric(unlist(edge_list))
            )

            route_stats <- route_edges_mapping |>
              left_join(edges, by = "edge_index") |>
              mutate(
                is_any_ci = osm_id %in% ci_osm_ids,
                bicycle_lts_alt = if_else(is_any_ci, 1, bicycle_lts)
              ) |>
              group_by(row_idx) |>
              summarise(
                lts1_alt_m = sum(length[bicycle_lts_alt == 1], na.rm = TRUE),
                lts2_alt_m = sum(length[bicycle_lts_alt == 2], na.rm = TRUE),
                lts3_alt_m = sum(length[bicycle_lts_alt == 3], na.rm = TRUE),
                lts4_alt_m = sum(length[bicycle_lts_alt == 4], na.rm = TRUE),
                total_edge_len = sum(length, na.rm = TRUE),
                .groups = "drop"
              ) |>
              mutate(
                route_pct_lts1_alternative = round(lts1_alt_m / pmax(total_edge_len, 1) * 100, 2),
                route_pct_lts2_alternative = round(lts2_alt_m / pmax(total_edge_len, 1) * 100, 2),
                route_pct_lts3_alternative = round(lts3_alt_m / pmax(total_edge_len, 1) * 100, 2),
                route_pct_lts4_alternative = round(lts4_alt_m / pmax(total_edge_len, 1) * 100, 2)
              ) |>
              select(-lts1_alt_m, -lts2_alt_m, -lts3_alt_m, -lts4_alt_m, -total_edge_len)

            # Reattach back to the route metrics
            metric_cols <- target_for_metrics |>
              mutate(row_idx = row_number()) |>
              left_join(route_stats, by = "row_idx") |>
              select(from_id, to_id, ends_with("_alternative"))

            # Calculate standard metrics again from target_for_metrics or trips to bind together
            stats <- trips |>
              st_drop_geometry() |>
              mutate(from_id = as.character(from_id), to_id = as.character(to_id)) |>
              group_by(from_id, to_id) |>
              summarise(
                total_duration = first(total_duration),
                total_distance = first(total_distance),
                euclidean_distance = first(euclidean_distance),
                route_ci_strong_m = first(route_ci_strong_m),
                route_ci_medium_m = first(route_ci_medium_m),
                route_ci_weak_m = first(route_ci_weak_m),
                route_ci_foot_m = first(route_ci_foot_m),
                route_pct_lts1 = first(route_pct_lts1),
                route_pct_lts2 = first(route_pct_lts2),
                route_pct_lts3 = first(route_pct_lts3),
                route_pct_lts4 = first(route_pct_lts4),
                route_interruptions_count = first(route_interruptions_count),
                .groups = "drop"
              ) |>
              left_join(metric_cols, by = c("from_id", "to_id")) |>
              mutate(year = yr, lts = lts_level)

            # preserve accessibility if available
            if ("access_15min_vol" %in% names(trips)) {
              acc_data <- trips |>
                st_drop_geometry() |>
                group_by(from_id, to_id) |>
                summarise(access_15min_vol = first(access_15min_vol), .groups = "drop")
              stats <- stats |> left_join(acc_data, by = c("from_id", "to_id"))
            } else {
              stats$access_15min_vol <- 0
            }

            all_stats[[paste0(yr, "_", lts_level)]] <- stats
          }
        }
      }
    }
  }

  if (length(all_stats) > 0) {
    df_combined <- bind_rows(all_stats)

    long_path <- file.path(city_dir, paste0(city_lower, "_routing_stats_all.rds"))
    saveRDS(df_combined, long_path)
    cat("  Saved updated routing stats with alternative metrics to:", basename(long_path), "\n")

    # Generate alternative and regular plots immediately for convenience
    for (lts_val in lts_levels) {
      lts_data <- df_combined |> filter(lts == lts_val)
      if (nrow(lts_data) > 0) {
        # Regular Plot
        city_summary_reg <- lts_data |>
          mutate(year = as.factor(paste0("20", year))) |>
          group_by(year) |>
          summarise(
            lts1 = mean(route_pct_lts1, na.rm = TRUE),
            lts2 = mean(route_pct_lts2, na.rm = TRUE),
            lts3 = mean(route_pct_lts3, na.rm = TRUE),
            lts4 = mean(route_pct_lts4, na.rm = TRUE),
            .groups = "drop"
          ) |>
          pivot_longer(-year, names_to = "LTS", values_to = "pct")

        p_reg <- ggplot(city_summary_reg, aes(y = fct_rev(year), x = pct, fill = LTS)) +
          geom_bar(stat = "identity", position = "stack") +
          scale_fill_viridis_d(option = "cividis", direction = -1) +
          labs(
            title = paste(tools::toTitleCase(city), "- Route Usage by LTS (Original)"),
            subtitle = paste("Percentage of LTS road types driven on routes (LTS", lts_val, "max)"),
            x = "Percentage (%)",
            y = "Year",
            fill = "Network LTS Level"
          ) +
          theme_minimal()

        results_dir <- file.path(city_dir, "results")
        dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)
        ggsave(file.path(results_dir, paste0("plot_route_lts_usage_lts", lts_val, ".png")), p_reg, width = 8, height = 4)
        cat("  Saved regular route LTS usage plot (LTS =", lts_val, ") to results folder.\n")

        # Alternative Plot
        city_summary <- lts_data |>
          mutate(year = as.factor(paste0("20", year))) |>
          group_by(year) |>
          summarise(
            lts1 = mean(route_pct_lts1_alternative, na.rm = TRUE),
            lts2 = mean(route_pct_lts2_alternative, na.rm = TRUE),
            lts3 = mean(route_pct_lts3_alternative, na.rm = TRUE),
            lts4 = mean(route_pct_lts4_alternative, na.rm = TRUE),
            .groups = "drop"
          ) |>
          pivot_longer(-year, names_to = "LTS", values_to = "pct")

        p_alt <- ggplot(city_summary, aes(y = fct_rev(year), x = pct, fill = LTS)) +
          geom_bar(stat = "identity", position = "stack") +
          scale_fill_viridis_d(option = "cividis", direction = -1) +
          labs(
            title = paste(tools::toTitleCase(city), "- Route Usage by LTS (Alternative)"),
            subtitle = paste0("Percentage of LTS road types driven on routes (LTS ", lts_val, " max, CI=1)"),
            x = "Percentage (%)",
            y = "Year",
            fill = "Network LTS Level"
          ) +
          theme_minimal()

        results_dir <- file.path(city_dir, "results")
        dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)
        ggsave(file.path(results_dir, paste0("plot_route_lts_usage_alternative_lts", lts_val, ".png")), p_alt, width = 8, height = 4)
        cat("  Saved alternative route LTS usage plot (LTS =", lts_val, ") to results folder.\n")
      }
    }
  }
}

cat("Done adding alternative LTS metrics.\n")
