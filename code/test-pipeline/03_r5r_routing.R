# 03_r5r_routing.R
# Setup networks and calculate detailed itineraries one by one to save RAM/Disk

library(tidyverse)
library(sf)
# Allocate memory securely without overflowing the 16GB RAM laptop limitations
# Load global configuration
source("code/test-pipeline/config.R")
options(java.parameters = java_mem)
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

        # Move PBF to r5r_dir if needed for setup
        temp_pbf <- file.path(r5r_dir, basename(pbf_file))
        if (!file.exists(network_dat) && file.exists(pbf_file)) {
            file.copy(pbf_file, temp_pbf, overwrite = TRUE)
        }

        cat(paste("Setting up r5r network for", city, "year", yr, "...\n"))
        tryCatch(
            {
                # Build / load network
                r5_engine <- build_network(data_path = r5r_dir, verbose = FALSE)

                # Extract LTS
                lts_gpkg <- file.path(r5r_dir, paste0(city_lower, "_", yr, "_lts.gpkg"))
                if (!file.exists(lts_gpkg)) {
                    edges <- street_network_to_sf(r5_engine) |> purrr::pluck("edges")
                    st_write(edges, lts_gpkg, append = FALSE, quiet = TRUE)
                    rm(edges)
                }

                print(paste("Entering LTS loop for Year", yr))
                # Calculate routing for LTS 1 to 4
                for (lts_level in 1:4) {
                    res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
                    print(paste("Checking", res_file))
                    if (!file.exists(res_file)) {
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
                    } else {
                        print(paste("  FILE EXISTS - SKIPPING", res_file))
                    }
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
                if (file.exists(pbf_file)) {
                    file.remove(pbf_file)
                    
                    cat("  Deleted intermediate raw PBF and associated mapdb files:", pbf_file, "\n")
                }
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
