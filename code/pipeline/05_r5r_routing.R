# 05_r5r_routing.R
# Setup networks and calculate detailed itineraries one by one to save RAM/Disk

library(tidyverse)
library(sf)
library(accessibility)
library(lwgeom)
# Allocate memory securely without overflowing the 16GB RAM laptop limitations
# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run
options(java.parameters = java_mem)
cat("[DEBUG] Target cities in Step 03:", paste(target_cities, collapse = ", "), "\n")
library(r5r)

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)

    # Load OD pairs (skip if missing)
    origins_path <- file.path(city_dir, "origins.gpkg")
    dests_path <- file.path(city_dir, "destinations.gpkg")
    if (!file.exists(origins_path) || !file.exists(dests_path)) {
        warning(paste("Missing OD matrices for", city, "- skipping routing."))
        next
    }
    origins <- st_read(origins_path, quiet = TRUE)
    destinations <- st_read(dests_path, quiet = TRUE)

    # Format for r5r (requires data.frame with id, lon, lat)
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

    # Load real land use dataset (full grid) instead of using the destination samples
    land_use_path <- file.path(city_dir, "land_use.gpkg")
    if (!file.exists(land_use_path)) {
        warning(paste("Missing land_use.gpkg for", city, "- falling back to destination samples (will be incomplete!)"))
        dest_land_use <- data.frame(
            id = as.character(destinations$id),
            volume = destinations$volume
        )
        # Filter to unique IDs to satisfy accessibility package requirements
        dest_land_use <- dest_land_use[!duplicated(dest_land_use$id), ]
        land_use_r5 <- data.frame(
            id = dest_land_use$id,
            lon = st_coordinates(destinations)[!duplicated(destinations$id), 1],
            lat = st_coordinates(destinations)[!duplicated(destinations$id), 2]
        )
    } else {
        cat("  Loading city-wide land use grid for true accessibility...\n")
        land_use_sf <- st_read(land_use_path, quiet = TRUE)
        dest_land_use <- st_drop_geometry(land_use_sf) %>% mutate(id = as.character(id))
        land_use_r5 <- data.frame(
            id = dest_land_use$id,
            lon = st_coordinates(st_centroid(land_use_sf))[, 1],
            lat = st_coordinates(st_centroid(land_use_sf))[, 2]
        )
        rm(land_use_sf)
    }

    # --- Unique OD pair optimization ---
    # Since OD data uses H3 cell centroids, many trips share the same O-D pair.
    # We build a lookup of unique coordinate pairs, route only those, and rejoin.
    all_pairs <- data.frame(
        orig_lon = origins_df$lon,
        orig_lat = origins_df$lat,
        dest_lon = dests_df$lon,
        dest_lat = dests_df$lat,
        trip_id  = origins_df$id
    )
    # Create a pair key for deduplication
    all_pairs$pair_key <- paste(all_pairs$orig_lon, all_pairs$orig_lat,
        all_pairs$dest_lon, all_pairs$dest_lat,
        sep = "_"
    )
    unique_pairs <- all_pairs[!duplicated(all_pairs$pair_key), ]

    # Create unique origins/destinations for r5r
    unique_origins_df <- data.frame(
        id  = as.character(seq_len(nrow(unique_pairs))),
        lon = unique_pairs$orig_lon,
        lat = unique_pairs$orig_lat
    )
    unique_dests_df <- data.frame(
        id = as.character(seq_len(nrow(unique_pairs))),
        lon = unique_pairs$dest_lon,
        lat = unique_pairs$dest_lat,
        volume = 1L # each unique destination counts as 1 opportunity
    )

    cat(sprintf(
        "  [OD OPTIMIZATION] %d total trips -> %d unique OD pairs (%.0f%% reduction)\n",
        nrow(all_pairs), nrow(unique_pairs),
        (1 - nrow(unique_pairs) / nrow(all_pairs)) * 100
    ))

    # Build lookup to map unique pair results back to all trip IDs
    pair_key_to_uid <- setNames(unique_origins_df$id, unique_pairs$pair_key)
    all_pairs$unique_id <- pair_key_to_uid[all_pairs$pair_key]

    for (yr in years) {
        pbf_file <- file.path(city_dir, paste0(city_lower, "_", yr, ".osm.pbf"))
        r5r_dir <- file.path(city_dir, paste0("r5r_", yr))

        # Check if network already built by existence of network.dat
        network_dat <- file.path(r5r_dir, "network.dat")
        if (!file.exists(network_dat) && !file.exists(pbf_file)) {
            warning(paste("Missing historical PBF and network.dat for", city_lower, yr, "- skipping..."))
            next
        }

        dir.create(r5r_dir, showWarnings = FALSE, recursive = TRUE)

        # Move PBF and trigger rebuild if network is stale
        temp_pbf <- file.path(r5r_dir, basename(pbf_file))

        rebuild_needed <- FALSE
        if (!file.exists(network_dat) || FORCE_RERUN) {
            if (FORCE_RERUN && file.exists(network_dat)) {
                cat("  FORCE_RERUN is TRUE. Invalidating R5 cache...\n")
                file.remove(network_dat)
            }
            rebuild_needed <- TRUE
        } else if (file.exists(pbf_file)) {
            if (file.mtime(pbf_file) > file.mtime(network_dat)) {
                cat("  Detected updated Street Network (PBF). Invalidating R5 cache...\n")
                file.remove(network_dat)
                rebuild_needed <- TRUE
            }
        }

        if (rebuild_needed && file.exists(pbf_file)) {
            file.copy(pbf_file, temp_pbf, overwrite = TRUE)
        }

        cat(paste("Setting up r5r network for", city, "year", yr, "...\n"))
        tryCatch(
            {
                # Build / load network
                r5_engine <- build_network(data_path = r5r_dir, verbose = FALSE, overwrite = rebuild_needed)

                # Extract LTS
                lts_gpkg <- file.path(r5r_dir, paste0(city_lower, "_", yr, "_lts.gpkg"))

                # Robust check: file must exist AND be readable/not corrupt
                file_valid <- FALSE
                if (file.exists(lts_gpkg)) {
                    file_valid <- tryCatch(
                        {
                            # Just check if we can read the layer info
                            st_layers(lts_gpkg)
                            TRUE
                        },
                        error = function(e) FALSE
                    )
                }

                if (!file_valid) {
                    if (file.exists(lts_gpkg)) {
                        cat("  Detected corrupt or unreadable LTS file. Re-generating...\n")
                        file.remove(lts_gpkg)
                    }
                    edges_sf <- street_network_to_sf(r5_engine) |> purrr::pluck("edges")
                    st_write(edges_sf, lts_gpkg, append = FALSE, delete_dsn = TRUE, quiet = TRUE)
                    rm(edges_sf)
                }

                # Load edges and CI once per year to enrich routed trips with exposure metrics
                edges <- st_read(lts_gpkg, quiet = TRUE) |> st_drop_geometry()

                v_ext <- versions[which(years == yr)]
                ci_path <- file.path(city_dir, paste0(city_lower, "_ci_osmactive_", v_ext, ".gpkg"))

                ci_ids <- list(strong = c(), medium = c(), weak = c(), foot = c())
                if (file.exists(ci_path)) {
                    ci <- st_read(ci_path, quiet = TRUE)
                    if ("infra5" %in% names(ci)) {
                        # Map internal labels to the categories requested by user
                        ci_ids$strong <- ci$osm_id[ci$infra5 == "Separated cycling infrastructure"]
                        ci_ids$medium <- ci$osm_id[ci$infra5 == "Painted on-road cycle lane"]
                        ci_ids$weak <- ci$osm_id[ci$infra5 == "Mixed traffic (motor vehicles with light infra)"]
                        ci_ids$foot <- ci$osm_id[ci$infra5 == "Cycling on pedestrian infrastructure"]
                    }
                    rm(ci)
                }

                print(paste("Entering LTS loop for Year", yr))
                # Calculate routing for LTS levels defined in config
                for (lts_level in lts_levels) {
                    res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
                    res_file_long <- file.path(city_dir, paste0("trips_", city_lower, "_20", yr, "_lts", lts_level, ".rds"))

                    found_existing <- FALSE
                    if (file.exists(res_file)) {
                        check_file <- res_file
                        found_existing <- TRUE
                    } else if (file.exists(res_file_long)) {
                        check_file <- res_file_long
                        found_existing <- TRUE
                    }

                    if (found_existing) {
                        # Re-run if results are older than OD matrices OR older than the updated PBF network
                        od_updated <- file.mtime(check_file) < file.mtime(origins_path)
                        pbf_updated <- FALSE
                        if (file.exists(pbf_file)) {
                            pbf_updated <- file.mtime(check_file) < file.mtime(pbf_file)
                        } else {
                            # If PBF is missing, we MUST re-run if this is not the first scan
                            if (!file.exists(network_dat)) pbf_updated <- TRUE
                        }

                        if (FORCE_RERUN) {
                            cat("  FORCE_RERUN is TRUE. Ignoring existing results and re-running...\n")
                        } else if (od_updated) {
                            cat("  Existing results are older than updated OD matrix. Re-running...\n")
                        } else if (pbf_updated) {
                            cat("  Existing results are older than updated/missing Street Network. Re-running...\n")
                        } else {
                            # Check if existing file needs enriching with access_15min_vol
                            existing_trips <- readRDS(check_file)
                            if (!"access_15min_vol" %in% names(existing_trips)) {
                                cat(paste("  Valid results exist but MISSING access_15min_vol. Re-processing enrichment for:", check_file, "\n"))
                                # Carry on with this LTS level loop but signal to skip detailed_itineraries
                                trips_already_loaded <- existing_trips
                            } else {
                                cat(paste("  Valid results already exist - SKIPPING. Path:", check_file, "\n"))
                                rm(existing_trips)
                                next
                            }
                        }

                        # Triggered a re-run: delete the old RDS to force fresh computation
                        if (file.exists(check_file)) file.remove(check_file)
                    }

                    print(paste(
                        "  Calculating itineraries for Year", yr, "LTS", lts_level,
                        "(", nrow(unique_origins_df), "unique pairs )"
                    ))
                    enriching <- FALSE
                    if (exists("trips_already_loaded") && !is.null(trips_already_loaded)) {
                        cat("    Enrichment Mode: Re-processing metadata for existing routes...\n")
                        trips <- trips_already_loaded
                        enriching <- TRUE
                        rm(trips_already_loaded)
                        unique_trips <- data.frame()
                    } else {
                        unique_trips <- detailed_itineraries(
                            r5r_network = r5_engine,
                            origins = unique_origins_df,
                            destinations = unique_dests_df,
                            mode = "BICYCLE",
                            shortest_path = TRUE,
                            max_lts = lts_level,
                            progress = TRUE,
                            osm_link_ids = TRUE
                        )
                    }

                    # --- Metadata Processing (Exposure Metrics) ---
                    # If we have new unique_trips or if trips is missing exposure columns
                    needs_exposure <- FALSE
                    if (nrow(unique_trips) > 0) needs_exposure <- TRUE
                    if (enriching && !"route_ci_strong_m" %in% names(trips)) needs_exposure <- TRUE

                    if (needs_exposure) {
                        cat("    Calculating route-level exposure metrics (CI, LTS, circuity)...\n")

                        # Target for metrics calculation: unique_trips if new, otherwise trips (deduplicated for speed if possible)
                        target_for_metrics <- if (nrow(unique_trips) > 0) {
                            unique_trips
                        } else {
                            # In enrichment, trips might have 20k rows.
                            # We filter to unique from_id/to_id to speed up processing
                            trips %>%
                                group_by(from_id, to_id) %>%
                                slice(1) %>%
                                ungroup()
                        }

                        # Calculate Euclidean distance
                        target_for_metrics <- target_for_metrics %>%
                            mutate(
                                euclidean_distance = as.numeric(st_distance(
                                    lwgeom::st_startpoint(geometry),
                                    lwgeom::st_endpoint(geometry),
                                    by_element = TRUE
                                ))
                            )

                        edge_list_str <- as.character(target_for_metrics$edge_id_list)
                        edge_list <- strsplit(edge_list_str, ",")

                        route_edges_mapping <- data.frame(
                            row_idx = rep(1:nrow(target_for_metrics), lengths(edge_list)),
                            edge_index = as.numeric(unlist(edge_list))
                        )

                        route_stats <- route_edges_mapping %>%
                            left_join(edges, by = "edge_index") %>%
                            mutate(
                                is_strong = osm_id %in% ci_ids$strong,
                                is_medium = osm_id %in% ci_ids$medium,
                                is_weak   = osm_id %in% ci_ids$weak,
                                is_foot   = osm_id %in% ci_ids$foot,
                                is_any_ci = is_strong | is_medium | is_weak | is_foot
                            ) %>%
                            group_by(row_idx) %>%
                            summarise(
                                route_ci_strong_m = sum(length[is_strong], na.rm = TRUE),
                                route_ci_medium_m = sum(length[is_medium], na.rm = TRUE),
                                route_ci_weak_m = sum(length[is_weak], na.rm = TRUE),
                                route_ci_foot_m = sum(length[is_foot], na.rm = TRUE),
                                lts1_m = sum(length[bicycle_lts == 1], na.rm = TRUE),
                                lts2_m = sum(length[bicycle_lts == 2], na.rm = TRUE),
                                lts3_m = sum(length[bicycle_lts == 3], na.rm = TRUE),
                                lts4_m = sum(length[bicycle_lts == 4], na.rm = TRUE),
                                total_edge_len = sum(length, na.rm = TRUE),
                                route_interruptions_count = {
                                    ci_flag <- is_any_ci
                                    edge_len <- length
                                    n <- length(ci_flag)
                                    if (n <= 1) {
                                        0L
                                    } else {
                                        interruptions <- 0L
                                        non_ci_accum <- 0
                                        was_on_ci <- FALSE
                                        for (k in seq_len(n)) {
                                            if (is_any_ci[k]) {
                                                if (was_on_ci && non_ci_accum > 100) interruptions <- interruptions + 1L
                                                non_ci_accum <- 0
                                                was_on_ci <- TRUE
                                            } else {
                                                non_ci_accum <- non_ci_accum + ifelse(is.na(edge_len[k]), 0, edge_len[k])
                                            }
                                        }
                                        interruptions
                                    }
                                },
                                .groups = "drop"
                            ) %>%
                            mutate(
                                route_pct_lts1 = round(lts1_m / pmax(total_edge_len, 1) * 100, 2),
                                route_pct_lts2 = round(lts2_m / pmax(total_edge_len, 1) * 100, 2),
                                route_pct_lts3 = round(lts3_m / pmax(total_edge_len, 1) * 100, 2),
                                route_pct_lts4 = round(lts4_m / pmax(total_edge_len, 1) * 100, 2)
                            ) %>%
                            select(-lts1_m, -lts2_m, -lts3_m, -lts4_m, -total_edge_len)

                        target_for_metrics <- target_for_metrics %>%
                            mutate(row_idx = row_number()) %>%
                            left_join(route_stats, by = "row_idx") %>%
                            select(-row_idx) %>%
                            mutate(across(starts_with("route_"), ~ replace_na(., 0)))

                        if (!enriching) {
                            # Expand unique_trips to 20k rows
                            trips <- target_for_metrics %>%
                                inner_join(expansion_map, by = c("from_id" = "unique_id"), relationship = "many-to-many") %>%
                                mutate(from_id = trip_id, to_id = trip_id) %>%
                                select(-trip_id)
                        } else {
                            # Re-join metrics to existing 20k rows
                            trips <- trips %>%
                                left_join(st_drop_geometry(target_for_metrics) %>% select(from_id, to_id, starts_with("route_"), euclidean_distance), by = c("from_id", "to_id")) %>%
                                mutate(across(starts_with("route_"), ~ replace_na(., 0)))
                        }
                    }


                    # --- Accessibility (using full travel matrix to ensure correct volume sum) ---
                    avg_acc <- NA
                    if (nrow(trips) > 0) {
                        cat("    Calculating TRUE 15-min volume accessibility (Matrix to all H3 cells)...\n")

                        tryCatch(
                            {
                                # We need travel times from UNIQUE origins to ALL land use cells
                                ttm <- travel_time_matrix(
                                    r5r_network = r5_engine,
                                    origins = unique_origins_df,
                                    destinations = land_use_r5,
                                    mode = "BICYCLE",
                                    max_trip_duration = 15,
                                    max_lts = lts_level,
                                    verbose = FALSE
                                )

                                acc <- accessibility::cumulative_cutoff(
                                    travel_matrix = ttm,
                                    land_use_data = dest_land_use,
                                    opportunity = "volume",
                                    travel_cost = "travel_time",
                                    cutoff = 15
                                )

                                if (nrow(acc) > 0) {
                                    # Handle expansion carefully to not lose sf class
                                    acc_to_join <- acc %>%
                                        select(unique_id = id, access_15min_vol = volume) %>%
                                        mutate(unique_id = as.character(unique_id))

                                    # we join to 'trips' (which is the full 20k rows)
                                    # mapping back: trip_id is in from_id.
                                    trips_meta <- all_pairs %>%
                                        select(trip_id, unique_id) %>%
                                        mutate(trip_id = as.character(trip_id))

                                    trips_enriched <- trips %>%
                                        st_drop_geometry() %>%
                                        mutate(from_id = as.character(from_id)) %>%
                                        left_join(trips_meta, by = c("from_id" = "trip_id")) %>%
                                        left_join(acc_to_join, by = "unique_id") %>%
                                        mutate(access_15min_vol = replace_na(access_15min_vol, 0)) %>%
                                        select(-unique_id)

                                    # Re-attribute geometry
                                    geom_backup <- st_geometry(trips)
                                    trips <- trips_enriched
                                    st_geometry(trips) <- geom_backup

                                    avg_acc <- round(mean(trips$access_15min_vol, na.rm = TRUE))
                                }
                                rm(ttm, acc)
                            },
                            error = function(e) {
                                cat(paste("    [WARN] Accessibility failed:", e$message, "\n"))
                            }
                        )
                    }

                    saveRDS(trips, res_file)

                    # Export route finding metrics tracking how many successfully found a route
                    found_routes <- nrow(trips)
                    summary_file <- file.path(city_dir, "routing_summary.csv")
                    # Force year to integer to avoid type mismatch (integer vs character)
                    summary_row <- data.frame(
                        city = city_lower,
                        year = as.integer(yr),
                        lts = lts_level,
                        found_routes = found_routes,
                        access_15min_vol = avg_acc
                    )

                    if (!file.exists(summary_file)) {
                        write.csv(summary_row, summary_file, row.names = FALSE)
                    } else {
                        existing_summary <- read.csv(summary_file) |>
                            mutate(year = as.integer(year))

                        # Remove existing entry for this specific city/year/LTS to avoid duplicates
                        updated_summary <- existing_summary |>
                            filter(!(city == summary_row$city & year == summary_row$year & lts == summary_row$lts)) |>
                            bind_rows(summary_row)

                        write.csv(updated_summary, summary_file, row.names = FALSE)
                    }

                    rm(trips)
                    gc()
                }


                # Stop engine to free JVM limits
                stop_r5()
                rJava::.jgc(R.gc = TRUE)

                if (file.exists(temp_pbf)) {
                    file.remove(temp_pbf)

                    # Also remove the mapdb files created by r5r in r5r_dir
                    mapdb_file <- paste0(temp_pbf, ".mapdb")
                    mapdbp_file <- paste0(temp_pbf, ".mapdb.p")
                    if (file.exists(mapdb_file)) file.remove(mapdb_file)
                    if (file.exists(mapdbp_file)) file.remove(mapdbp_file)
                }
                # Keep the cropped PBF in the city_dir for future analysis/re-runs
            },
            error = function(cond) {
                warning(paste("r5r failed for", city, yr, ":", cond$message))
            }
        )

        # R memory flush
        gc()
    }
}
cat("r5r phase complete.\n")
