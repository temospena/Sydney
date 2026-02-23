# Load global configuration
source("code/test-pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run
options(java.parameters = java_mem)

library(tidyverse)
library(sf)
library(r5r)
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
  
  for (yr in years) {
    cat("Processing scenario for", city, "Year", yr, "\n")
    r5r_dir <- file.path(city_dir, paste0("r5r_", yr))
    
    r5_engine <- NULL
    tryCatch({
      r5_engine <- build_network(data_path = r5r_dir, verbose = FALSE)
    }, error = function(e) {
      warning("r5_engine could not be started for ", yr)
    })
    
    # Load CI layer
    # Fix: CI files are named with versions like 160101, but yr is "16"
    v_ext <- versions[which(years == yr)]
    ci_path <- file.path(city_dir, paste0(city_lower, "_ci_osmactive_", v_ext, ".gpkg"))
    
    ci <- NULL
    ci_osm_ids <- character(0)
    if (file.exists(ci_path)) {
      ci <- tryCatch({
        st_read(ci_path, quiet = TRUE)
      }, error = function(e) {
        warning("Could not read CI file: ", ci_path)
        NULL
      })
      if (!is.null(ci)) ci_osm_ids <- ci$osm_id
    }
    
    # Load edges (LTS info)
    edges_path <- file.path(r5r_dir, paste0(city_lower, "_", yr, "_lts.gpkg"))
    edges <- NULL
    if (file.exists(edges_path)) {
      edges <- tryCatch({
        st_read(edges_path, quiet = TRUE) |> 
          st_drop_geometry() |>
          select(edge_index, osm_id, bicycle_lts, length, car, bicycle)
      }, error = function(e) {
        warning("Detected corrupt LTS file: ", edges_path, ". You should delete it to re-generate.")
        NULL
      })
    }
    
    # Calculate Overall Non-Routing Land Use network stats for the year
    total_road_m <- NA
    total_ci_m <- NA
    pct_ci_total <- NA
    pct_lts1_total <- NA
    pct_lts2_total <- NA
    pct_lts3_total <- NA
    pct_lts4_total <- NA
    
    ci_type_sep_m <- NA
    ci_type_paint_m <- NA
    ci_type_mixed_m <- NA
    ci_type_foot_m <- NA

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

    if (exists("ci")) {
      ci_lengths <- as.numeric(st_length(ci))
      total_ci_m <- sum(ci_lengths, na.rm = TRUE)
      
      if (!is.na(total_road_m)) {
        pct_ci_total <- round(total_ci_m / pmax(total_road_m, 1) * 100, 2)
      }
      
      if ("infra5" %in% names(ci)) {
        ci_types <- data.frame(infra5 = ci$infra5, len = ci_lengths) |>
          group_by(infra5) |> summarise(total_len = sum(len, na.rm = TRUE))
        
        get_ci_len <- function(type_name) {
          val <- ci_types$total_len[ci_types$infra5 == type_name]
          if (length(val) > 0) return(val[1]) else return(0)
        }
        
        ci_type_sep_m <- get_ci_len("Separated cycling infrastructure")
        ci_type_paint_m <- get_ci_len("Painted on-road cycle lane")
        ci_type_mixed_m <- get_ci_len("Mixed traffic (motor vehicles with light infra)")
        ci_type_foot_m <- get_ci_len("Cycling on pedestrian infrastructure")
      }
    }

    for (lts_level in 1:4) {
      cat("  LTS", lts_level, "...\n")
      
      row_data <- data.frame(
        city = city, 
        year = paste0("20", yr), 
        lts = lts_level, 
        population = NA, # Can be updated with true population later from People for bikes dataset
        avg_distance_m = NA, 
        avg_circuity = NA,
        avg_dist_change_pct = NA, # Value populated dynamically across full dataframe
        pct_ci_route = NA, 
        pct_lts1 = NA, 
        pct_lts2 = NA, 
        pct_lts3 = NA, 
        pct_lts4 = NA, 
        access_15min_vol = NA,
        total_road_m = total_road_m,
        total_ci_m = total_ci_m,
        pct_ci_total = pct_ci_total,
        pct_lts1_total = pct_lts1_total,
        pct_lts2_total = pct_lts2_total,
        pct_lts3_total = pct_lts3_total,
        pct_lts4_total = pct_lts4_total,
        ci_type_sep_m = ci_type_sep_m,
        ci_type_paint_m = ci_type_paint_m,
        ci_type_mixed_m = ci_type_mixed_m,
        ci_type_foot_m = ci_type_foot_m
      )
      
      # 10. Estimate Accessibility
      if (!is.null(r5_engine)) {
        tryCatch({
          acc <- accessibility(
            r5r_network = r5_engine,
            origins = origins_df,
            destinations = dests_df,
            mode = "BICYCLE",
            opportunities_colnames = "volume",
            decay_function = "step",
            cutoffs = 15,
            max_lts = lts_level,
            verbose = FALSE,
            progress = FALSE
          )
          if (nrow(acc) > 0) {
            row_data$access_15min_vol <- mean(acc$accessibility, na.rm = TRUE)
          }
        }, error = function(e) {
            warning("Accessibility calculation failed for LTS ", lts_level)
        })
      }
      
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
            cat("    Found", nrow(trips), "trips in", basename(trips_to_read), "\n")
          
          # 6 & 9: Snapped distances and circuity
          trips <- trips |>
            mutate(
              snapped_start = lwgeom::st_startpoint(geometry),
              snapped_end = lwgeom::st_endpoint(geometry),
              linear_distance = as.numeric(st_distance(snapped_start, snapped_end, by_element = TRUE)),
              circuity = total_distance / pmax(linear_distance, 1) # avoid div0
            ) |> select(-snapped_start, -snapped_end)
          
          row_data$avg_distance_m <- round(mean(trips$total_distance, na.rm = TRUE), 2)
          row_data$avg_circuity <- round(mean(trips$circuity, na.rm = TRUE), 2)
          
          # 8: Percentage CI and LTS lengths per route
          if (!is.null(edges)) {
            trips_df <- trips |> st_drop_geometry() |> mutate(row_idx = row_number())
            edge_list_clean <- stringr::str_extract_all(trips_df$edge_id_list, "\\d+")
            
            route_edges <- data.frame(
                row_idx = rep(trips_df$row_idx, lengths(edge_list_clean)),
                edge_index = as.numeric(unlist(edge_list_clean))
            )
            
            # Left join edges
            route_edges <- route_edges |> left_join(edges, by = "edge_index")
            
            route_stats <- route_edges |>
              group_by(row_idx) |>
              summarise(
                total_edge_len = sum(length, na.rm = TRUE),
                ci_len = sum(length[osm_id %in% ci_osm_ids], na.rm = TRUE),
                lts1_len = sum(length[bicycle_lts == 1], na.rm = TRUE),
                lts2_len = sum(length[bicycle_lts == 2], na.rm = TRUE),
                lts3_len = sum(length[bicycle_lts == 3], na.rm = TRUE),
                lts4_len = sum(length[bicycle_lts == 4], na.rm = TRUE)
              )
              
            trips_df <- trips_df |> left_join(route_stats, by = "row_idx") |>
              mutate(
                pct_ci = ci_len / pmax(total_edge_len, 1),
                pct_lts1 = lts1_len / pmax(total_edge_len, 1),
                pct_lts2 = lts2_len / pmax(total_edge_len, 1),
                pct_lts3 = lts3_len / pmax(total_edge_len, 1),
                pct_lts4 = lts4_len / pmax(total_edge_len, 1)
              )
              
            row_data$pct_ci_route <- round(mean(trips_df$pct_ci, na.rm = TRUE) * 100, 2)
            row_data$pct_lts1 <- round(mean(trips_df$pct_lts1, na.rm = TRUE) * 100, 2)
            row_data$pct_lts2 <- round(mean(trips_df$pct_lts2, na.rm = TRUE) * 100, 2)
            row_data$pct_lts3 <- round(mean(trips_df$pct_lts3, na.rm = TRUE) * 100, 2)
            row_data$pct_lts4 <- round(mean(trips_df$pct_lts4, na.rm = TRUE) * 100, 2)
          }
        }
      } else {
          cat("    [MISSING] No itinerary file found for Year", yr, "(LTS", lts_level, "). Checked path:", res_file, "\n")
      }
      final_dataset[[length(final_dataset) + 1]] <- row_data
    }
    
    if (!is.null(r5_engine)) {
      stop_r5()
      rJava::.jgc(R.gc = TRUE)
    }
  }
}

if (length(final_dataset) == 0) {
    cat("No new data rows estimated for", target_cities, ". Skipping metrics finalization.\n")
} else {
    final_df <- bind_rows(final_dataset) |>
  group_by(city, lts) |>
  arrange(year) |>
  mutate(
    baseline_dist = first(avg_distance_m[year == "2016"]),
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
    mutate(city = tools::toTitleCase(city)) # Match city case format
  
  # Ensure column names match before join! final_df uses character city
  final_df <- final_df |> left_join(all_sums, by = c("city", "year", "lts"))
}

out_csv <- file.path(data_dir, "final_city_estimations.csv")

# INCREMENTAL UPDATE LOGIC:
if (file.exists(out_csv)) {
  existing_df <- read.csv(out_csv)
  # Filter out rows for the cities we just processed to avoid duplication
  processed_cities <- unique(final_df$city)
  existing_df <- existing_df %>% filter(!(city %in% processed_cities))
  
  # Merge new data with old
  final_df <- bind_rows(existing_df, final_df)
}

    write.csv(final_df, out_csv, row.names = FALSE)
    cat("Dataset dynamically updated and saved to:\n", out_csv, "\n")
}
