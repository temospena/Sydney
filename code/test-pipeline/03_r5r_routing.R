# 03_r5r_routing.R
# Setup networks and calculate detailed itineraries one by one to save RAM/Disk

library(tidyverse)
library(sf)
# Allocate memory securely without overflowing the 16GB RAM laptop limitations
# Load global configuration
source("code/test-pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run
options(java.parameters = java_mem)
cat("[DEBUG] Target cities in Step 03:", paste(target_cities, collapse=", "), "\n")
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
        lat = st_coordinates(destinations)[, 2]
    )

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
                r5_engine <- build_network(data_path = r5r_dir, verbose = FALSE)

                # Extract LTS
                lts_gpkg <- file.path(r5r_dir, paste0(city_lower, "_", yr, "_lts.gpkg"))
                
                # Robust check: file must exist AND be readable/not corrupt
                file_valid <- FALSE
                if (file.exists(lts_gpkg)) {
                    file_valid <- tryCatch({
                        # Just check if we can read the layer info
                        st_layers(lts_gpkg)
                        TRUE
                    }, error = function(e) FALSE)
                }

                if (!file_valid) {
                    if (file.exists(lts_gpkg)) {
                        cat("  Detected corrupt or unreadable LTS file. Re-generating...\n")
                        file.remove(lts_gpkg)
                    }
                    edges <- street_network_to_sf(r5_engine) |> purrr::pluck("edges")
                    st_write(edges, lts_gpkg, append = FALSE, delete_dsn = TRUE, quiet = TRUE)
                    rm(edges)
                }

                print(paste("Entering LTS loop for Year", yr))
                # Calculate routing for LTS 1 to 4
                for (lts_level in 1:4) {
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
                        }
                        
                        if (FORCE_RERUN) {
                            cat("  FORCE_RERUN is TRUE. Ignoring existing results and re-running...\n")
                        } else if (od_updated) {
                            cat("  Existing results are older than updated OD matrix. Re-running...\n")
                        } else if (pbf_updated) {
                            cat("  Existing results are older than updated Street Network (PBF). Re-running...\n")
                        } else {
                            cat(paste("  Valid results already exist - SKIPPING. Path:", check_file, "\n"))
                            next
                        }
                    }

                    print(paste("  Calculating itineraries for Year", yr, "LTS", lts_level))
                    trips <- detailed_itineraries(
                            r5r_network = r5_engine,
                            origins = origins_df,
                            destinations = dests_df,
                            mode = "BICYCLE",
                            shortest_path = TRUE,
                            max_lts = lts_level,
                            progress = TRUE, # know when it is done and how many routes are found
                            # verbose = FALSE, # hide warning messages
                            osm_link_ids = TRUE
                        )
                        saveRDS(trips, res_file)

                        # Export route finding metrics tracking how many successfully found a route
                        found_routes <- nrow(trips)
                        summary_file <- file.path(city_dir, "routing_summary.csv")
                        summary_row <- data.frame(city = city_lower, year = yr, lts = lts_level, found_routes = found_routes)
                        if (!file.exists(summary_file)) {
                            write.csv(summary_row, summary_file, row.names = FALSE)
                        } else {
                            write.table(summary_row, summary_file, append = TRUE, sep = ",", col.names = FALSE, row.names = FALSE)
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
