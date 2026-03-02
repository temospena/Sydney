# 07_final_metrics.R
# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run
options(java.parameters = java_mem)

library(tidyverse)
library(sf)
library(lwgeom)
library(stringr)

final_dataset <- list()

cat("Starting Step 6, 8, 9, 10 Metrics Aggregation...\n")

for (city in target_cities) {
  city_lower <- tolower(city)
  city_dir <- file.path(data_dir, city_lower)

  origins_path <- file.path(city_dir, "origins.gpkg")
  dests_path <- file.path(city_dir, "destinations.gpkg")
  if (!file.exists(origins_path) || !file.exists(dests_path)) {
    warning(paste("Missing OD matrices for", city, "- skipping."))
    next
  }

  origins <- st_read(origins_path, quiet = TRUE)
  destinations <- st_read(dests_path, quiet = TRUE)

  origins_df <- data.frame(
    id = as.character(origins$id),
    lon = st_coordinates(origins)[, 1],
    lat = st_coordinates(origins)[, 2]
  )

  dests_df <- data.frame(
    id = as.character(destinations$id),
    lon = st_coordinates(destinations)[, 1],
    lat = st_coordinates(destinations)[, 2],
    volume = destinations$volume
  )

  # Calculate linear distances for fixed OD pairs once per city
  # Note: r5r routes head-to-head (Origin i to Destination i)
  cat("  Pre-calculating linear distances for all sampled OD pairs...\n")
  od_pairs_lookup <- data.frame(
    from_id = origins_df$id,
    to_id = dests_df$id,
    linear_distance = sqrt(
      ((dests_df$lon - origins_df$lon) * 111320 * cos(origins_df$lat * pi / 180))^2 +
        ((dests_df$lat - origins_df$lat) * 111320)^2
    )
  )

  # Read population
  city_list_path <- if (requireNamespace("here", quietly = TRUE)) {
    here::here("data/city_list.txt")
  } else {
    "data/city_list.txt"
  }

  if (!file.exists(city_list_path)) city_list_path <- "../../data/city_list.txt"

  city_population <- NA
  if (file.exists(city_list_path)) {
    city_list <- read.csv(city_list_path, header = FALSE)
    match_idx <- which(tolower(city_list$V1) == city_lower)
    if (length(match_idx) > 0) {
      city_population <- city_list$V4[match_idx[1]]
    }
  }

  for (yr in years) {
    cat("Processing scenario for", city, "Year", yr, "\n")
    r5r_dir <- file.path(city_dir, paste0("r5r_", yr))


    # Load CI layer
    # Fix: CI files are named with versions like 160101, but yr is "16"
    v_ext <- versions[which(years == yr)]
    ci_path <- file.path(city_dir, paste0(city_lower, "_ci_osmactive_", v_ext, ".gpkg"))

    ci <- NULL
    ci_osm_ids <- character(0)
    ci_osm_ids_sep <- character(0)
    ci_osm_ids_paint <- character(0)
    ci_osm_ids_mixed <- character(0)
    ci_osm_ids_foot <- character(0)

    if (file.exists(ci_path)) {
      ci <- tryCatch(
        {
          st_read(ci_path, quiet = TRUE)
        },
        error = function(e) {
          warning("Could not read CI file: ", ci_path)
          NULL
        }
      )
      if (!is.null(ci)) {
        ci_osm_ids <- ci$osm_id
        if ("infra5" %in% names(ci)) {
          ci_osm_ids_sep <- ci$osm_id[ci$infra5 == "Separated cycling infrastructure"]
          ci_osm_ids_paint <- ci$osm_id[ci$infra5 == "Painted on-road cycle lane"]
          ci_osm_ids_mixed <- ci$osm_id[ci$infra5 == "Mixed traffic (motor vehicles with light infra)"]
          ci_osm_ids_foot <- ci$osm_id[ci$infra5 == "Cycling on pedestrian infrastructure"]
        }
      }
    }

    # Load edges (LTS info)
    edges_path <- file.path(r5r_dir, paste0(city_lower, "_", yr, "_lts.gpkg"))
    edges <- NULL
    if (file.exists(edges_path)) {
      edges <- tryCatch(
        {
          st_read(edges_path, quiet = TRUE) |>
            st_drop_geometry() |>
            select(edge_index, osm_id, bicycle_lts, length, car, bicycle)
        },
        error = function(e) {
          warning("Detected corrupt LTS file: ", edges_path, ". You should delete it to re-generate.")
          NULL
        }
      )
    }

    # Calculate Overall Non-Routing Land Use network stats for the year
    # Initialize as 0 to avoid NA issues when summation happens
    total_road_m <- 0
    total_ci_m <- 0
    pct_ci_total <- 0
    pct_lts1_total <- 0
    pct_lts2_total <- 0
    pct_lts3_total <- 0
    pct_lts4_total <- 0

    ci_type_sep_m <- 0
    ci_type_paint_m <- 0
    ci_type_mixed_m <- 0
    ci_type_foot_m <- 0

    if (!is.null(edges)) {
      # Total road length without pedestrians (car or bicycle access allowed)
      valid_edges <- edges |> filter(car == "TRUE" | bicycle == "TRUE")
      total_road_m <- sum(valid_edges$length, na.rm = TRUE)

      lts1_m <- sum(valid_edges$length[valid_edges$bicycle_lts == 1], na.rm = TRUE)
      lts2_m <- sum(valid_edges$length[valid_edges$bicycle_lts == 2], na.rm = TRUE)
      lts3_m <- sum(valid_edges$length[valid_edges$bicycle_lts == 3], na.rm = TRUE)
      lts4_m <- sum(valid_edges$length[valid_edges$bicycle_lts == 4], na.rm = TRUE)

      pct_lts1_total <- round(lts1_m / pmax(total_road_m, 1) * 100, 2)
      pct_lts2_total <- round(lts2_m / pmax(total_road_m, 1) * 100, 2)
      pct_lts3_total <- round(lts3_m / pmax(total_road_m, 1) * 100, 2)
      pct_lts4_total <- round(lts4_m / pmax(total_road_m, 1) * 100, 2)
    }

    if (!is.null(ci)) {
      ci_lengths <- as.numeric(st_length(ci))
      total_ci_m <- round(sum(ci_lengths, na.rm = TRUE))

      if (total_road_m > 0) {
        pct_ci_total <- round(total_ci_m / total_road_m * 100, 2)
      }

      if ("infra5" %in% names(ci)) {
        ci_types <- data.frame(infra5 = as.character(ci$infra5), len = ci_lengths) |>
          group_by(infra5) |>
          summarise(total_len = sum(len, na.rm = TRUE), .groups = "drop")

        get_ci_len <- function(type_names) {
          val <- ci_types$total_len[ci_types$infra5 %in% type_names]
          if (length(val) > 0) {
            return(sum(val))
          } else {
            return(0)
          }
        }

        # Use strict single labels (extraction rerun will ensure these are present)
        ci_type_sep_m <- get_ci_len("Separated cycling infrastructure")
        ci_type_paint_m <- get_ci_len("Painted on-road cycle lane")
        ci_type_mixed_m <- get_ci_len("Mixed traffic (motor vehicles with light infra)")
        ci_type_foot_m <- get_ci_len("Cycling on pedestrian infrastructure")
      }
    }

    for (lts_level in lts_levels) {
      cat("  LTS", lts_level, "...\n")

      row_data <- data.frame(
        city = city,
        year = paste0("20", yr),
        lts = lts_level,
        population = city_population,
        avg_distance_m = NA,
        avg_circuity = NA,
        avg_dist_change_pct = NA, # Value populated dynamically across full dataframe
        avg_duration_min = NA,
        avg_ci_interruptions = NA,
        pct_ci_route = NA,
        pct_ci_route_sep = NA,
        pct_ci_route_paint = NA,
        pct_ci_route_mixed = NA,
        pct_ci_route_foot = NA,
        pct_lts1 = NA,
        pct_lts2 = NA,
        pct_lts3 = NA,
        pct_lts4 = NA,
        total_road_m = total_road_m,
        total_ci_m = total_ci_m,
        pct_ci_total = pct_ci_total,
        pct_lts1_total = pct_lts1_total,
        pct_lts2_total = pct_lts2_total,
        pct_lts3_total = pct_lts3_total,
        pct_lts4_total = pct_lts4_total,
        ci_type_sep_m = round(ci_type_sep_m, 0),
        ci_type_paint_m = round(ci_type_paint_m, 0),
        ci_type_mixed_m = round(ci_type_mixed_m, 0),
        ci_type_foot_m = round(ci_type_foot_m, 0),
        processing_time_minutes = NA
      )


      # Load generated itineraries for 6, 8, 9
      res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
      res_file_long <- file.path(city_dir, paste0("trips_", city_lower, "_20", yr, "_lts", lts_level, ".rds"))

      trips_to_read <- NULL
      if (file.exists(res_file)) {
        trips_to_read <- res_file
      } else if (file.exists(res_file_long)) {
        trips_to_read <- res_file_long
      }

      if (!is.null(trips_to_read)) {
        trips <- readRDS(trips_to_read)
        if (nrow(trips) > 0) {
          cat("    Processing", nrow(trips), "trips (optimized lookup mode)...\n")

          # Drop geometry immediately
          trips <- trips |> st_drop_geometry()

          # Join pre-calculated linear distances for speed and consistency
          trips <- trips |>
            left_join(od_pairs_lookup, by = c("from_id", "to_id")) |>
            mutate(
              circuity = total_distance / pmax(linear_distance, 1)
            )

          row_data$avg_distance_m <- round(mean(trips$total_distance, na.rm = TRUE), 2)
          row_data$avg_circuity <- round(mean(trips$circuity, na.rm = TRUE), 2)

          # Average duration in minutes (r5r returns total_duration in minutes)
          if ("total_duration" %in% names(trips)) {
            row_data$avg_duration_min <- round(mean(trips$total_duration, na.rm = TRUE), 2)
          }

          # 8: Percentage CI and LTS lengths per route
          if (!is.null(edges)) {
            # Use faster strsplit and unnesting instead of regex
            edge_list <- strsplit(as.character(trips$edge_id_list), ",")

            route_edges <- data.frame(
              row_idx = rep(1:nrow(trips), lengths(edge_list)),
              edge_index = as.numeric(unlist(edge_list))
            )

            # Left join edges (edges is already st_drop_geometry)
            # Use only necessary columns to keep join light
            route_stats <- route_edges |>
              left_join(edges, by = "edge_index") |>
              group_by(row_idx) |>
              summarise(
                total_edge_len = sum(length, na.rm = TRUE),
                ci_len = sum(length[osm_id %in% ci_osm_ids], na.rm = TRUE),
                ci_sep_len = sum(length[osm_id %in% ci_osm_ids_sep], na.rm = TRUE),
                ci_paint_len = sum(length[osm_id %in% ci_osm_ids_paint], na.rm = TRUE),
                ci_mixed_len = sum(length[osm_id %in% ci_osm_ids_mixed], na.rm = TRUE),
                ci_foot_len = sum(length[osm_id %in% ci_osm_ids_foot], na.rm = TRUE),
                lts1_len = sum(length[bicycle_lts == 1], na.rm = TRUE),
                lts2_len = sum(length[bicycle_lts == 2], na.rm = TRUE),
                lts3_len = sum(length[bicycle_lts == 3], na.rm = TRUE),
                lts4_len = sum(length[bicycle_lts == 4], na.rm = TRUE),
                .groups = "drop"
              )

            final_trips <- trips |>
              mutate(row_idx = row_number()) |>
              left_join(route_stats, by = "row_idx") |>
              mutate(
                pct_ci = ci_len / pmax(total_edge_len, 1),
                pct_ci_sep = ci_sep_len / pmax(total_edge_len, 1),
                pct_ci_paint = ci_paint_len / pmax(total_edge_len, 1),
                pct_ci_mixed = ci_mixed_len / pmax(total_edge_len, 1),
                pct_ci_foot = ci_foot_len / pmax(total_edge_len, 1),
                pct_lts1 = lts1_len / pmax(total_edge_len, 1),
                pct_lts2 = lts2_len / pmax(total_edge_len, 1),
                pct_lts3 = lts3_len / pmax(total_edge_len, 1),
                pct_lts4 = lts4_len / pmax(total_edge_len, 1)
              )

            row_data$pct_ci_route <- round(mean(final_trips$pct_ci, na.rm = TRUE) * 100, 2)
            row_data$pct_ci_route_sep <- round(mean(final_trips$pct_ci_sep, na.rm = TRUE) * 100, 2)
            row_data$pct_ci_route_paint <- round(mean(final_trips$pct_ci_paint, na.rm = TRUE) * 100, 2)
            row_data$pct_ci_route_mixed <- round(mean(final_trips$pct_ci_mixed, na.rm = TRUE) * 100, 2)
            row_data$pct_ci_route_foot <- round(mean(final_trips$pct_ci_foot, na.rm = TRUE) * 100, 2)
            row_data$pct_lts1 <- round(mean(final_trips$pct_lts1, na.rm = TRUE) * 100, 2)
            row_data$pct_lts2 <- round(mean(final_trips$pct_lts2, na.rm = TRUE) * 100, 2)
            row_data$pct_lts3 <- round(mean(final_trips$pct_lts3, na.rm = TRUE) * 100, 2)
            row_data$pct_lts4 <- round(mean(final_trips$pct_lts4, na.rm = TRUE) * 100, 2)

            # CI Interruptions: count non-CI gaps > 100m per route
            # For each route, walk edges in order. When consecutive non-CI edges
            # accumulate > 100m and are followed by CI, that's 1 interruption.
            route_edges_ci <- route_edges |>
              left_join(edges, by = "edge_index") |>
              mutate(is_ci = osm_id %in% ci_osm_ids)

            ci_interruptions_per_route <- route_edges_ci |>
              arrange(row_idx, edge_index) |>
              group_by(row_idx) |>
              summarise(
                n_interruptions = {
                  ci_flag <- is_ci
                  edge_len <- length
                  n <- length(ci_flag)
                  if (n == 0 || all(is.na(ci_flag))) {
                    0L
                  } else {
                    interruptions <- 0L
                    non_ci_accum <- 0
                    was_on_ci <- FALSE
                    for (k in seq_len(n)) {
                      if (is.na(ci_flag[k])) next
                      if (ci_flag[k]) {
                        # Entering CI: if we had accumulated > 100m of non-CI, count it
                        if (was_on_ci && non_ci_accum > 100) {
                          interruptions <- interruptions + 1L
                        }
                        non_ci_accum <- 0
                        was_on_ci <- TRUE
                      } else {
                        # On non-CI road
                        non_ci_accum <- non_ci_accum + ifelse(is.na(edge_len[k]), 0, edge_len[k])
                      }
                    }
                    interruptions
                  }
                },
                .groups = "drop"
              )

            row_data$avg_ci_interruptions <- round(mean(ci_interruptions_per_route$n_interruptions, na.rm = TRUE), 2)
          }

          final_dataset[[length(final_dataset) + 1]] <- row_data
        }
      } else {
        cat("    [MISSING] No itinerary file found for Year", yr, "(LTS", lts_level, "). Checked path:", res_file, ". Skipping to avoid overwriting with NAs.\n")
      }
    }
  }
}

if (length(final_dataset) == 0) {
  cat("No new data rows estimated for", target_cities, ". Skipping metrics finalization.\n")
} else {
  # Add timestamp for the entire run
  current_timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

  final_df <- bind_rows(final_dataset) |>
    mutate(run_timestamp = current_timestamp) |>
    group_by(city, lts) |>
    arrange(year) |>
    mutate(
      baseline_dist = first(avg_distance_m), # uses smallest year after arrange(year)
      avg_dist_change_pct = round((avg_distance_m - baseline_dist) / pmax(baseline_dist, 1) * 100, 2)
    ) |>
    select(-baseline_dist) |>
    ungroup()

  # Read routing_summary files to join found_routes metric
  summaries <- list()
  for (city in target_cities) {
    sum_file <- file.path(data_dir, tolower(city), "routing_summary.csv")
    if (file.exists(sum_file)) {
      sum_df <- read.csv(sum_file) |>
        mutate(year = paste0("20", year))
      summaries[[city]] <- sum_df
    }
  }
  if (length(summaries) > 0) {
    all_sums <- bind_rows(summaries) |>
      mutate(city = tools::toTitleCase(city)) |>
      group_by(city) |>
      slice_tail(n = length(years) * length(lts_levels)) |> # last complete run: n_years × n LTS levels
      ungroup()

    final_df <- final_df |> left_join(all_sums, by = c("city", "year", "lts"))
  }

  # 11. Save individual city results to their results folder
  for (city in unique(final_df$city)) {
    city_results_dir <- file.path(data_dir, tolower(city), "results")
    dir.create(city_results_dir, recursive = TRUE, showWarnings = FALSE)

    city_est_file <- file.path(city_results_dir, paste0("estimations_", current_timestamp, ".csv"))
    city_data <- final_df |> filter(city == !!city)
    write.csv(city_data, city_est_file, row.names = FALSE)
    cat(sprintf("  Saved local city results to: %s/results/%s\n", tolower(city), basename(city_est_file)))
  }

  out_csv <- file.path(data_dir, "final_city_estimations.csv")

  # INCREMENTAL UPDATE LOGIC (Ensure no duplicates):
  if (file.exists(out_csv)) {
    existing_df <- read.csv(out_csv) |> mutate(year = as.character(year))

    # Identify keys in the new data
    new_keys <- final_df |>
      select(city, year, lts) |>
      distinct() |>
      mutate(key = paste(city, year, lts, sep = "_")) |>
      pull(key)

    # Filter out existing rows that match the new keys
    # This effectively "replaces" them with the latest version
    existing_df <- existing_df %>%
      mutate(temp_key = paste(city, year, lts, sep = "_")) %>%
      filter(!(temp_key %in% new_keys)) %>%
      select(-temp_key)

    # Merge new data with filtered old data
    final_df <- bind_rows(existing_df, final_df)
  }

  # Ensure columns are in a consistent order and deduplicate across all cities
  final_df <- final_df |>
    select(city, year, lts, run_timestamp, everything()) |>
    group_by(city, year, lts) |>
    slice_tail(n = 1) |>
    ungroup() |>
    arrange(city, year, lts)

  write.csv(final_df, out_csv, row.names = FALSE)
  cat("Dataset dynamically updated and saved to:\n", out_csv, "\n")
}
