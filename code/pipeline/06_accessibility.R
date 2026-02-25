# 06_accessibility.R
# Calculate accessibility metrics separately from routing

library(tidyverse)
library(sf)
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run
options(java.parameters = java_mem)
library(r5r)

cat("[DEBUG] Target cities for Accessibility:", paste(target_cities, collapse = ", "), "\n")

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)

    # Load OD pairs
    origins_path <- file.path(city_dir, "origins.gpkg")
    dests_path <- file.path(city_dir, "destinations.gpkg")
    if (!file.exists(origins_path) || !file.exists(dests_path)) {
        warning(paste("Missing OD matrices for", city, "- skipping accessibility."))
        next
    }
    origins <- st_read(origins_path, quiet = TRUE)
    destinations <- st_read(dests_path, quiet = TRUE)

    # Format for r5r
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

    all_city_acc <- list()

    for (yr in years) {
        r5r_dir <- file.path(city_dir, paste0("r5r_", yr))
        if (!dir.exists(r5r_dir)) {
            cat(paste("  [SKIP] R5 network directory does not exist for", city, yr, "\n"))
            next
        }

        cat(paste("Calculating accessibility for", city, "year", yr, "...\n"))

        tryCatch(
            {
                # Build / load network
                r5_engine <- build_network(data_path = r5r_dir, verbose = FALSE)

                for (lts_level in 1:4) {
                    cat(paste("    LTS", lts_level, "... "))
                    acc <- r5r::accessibility(
                        r5r_network = r5_engine,
                        origins = origins_df,
                        destinations = dests_df,
                        opportunities = "volume",
                        cutoff = 15,
                        mode = "BICYCLE",
                        max_lts = lts_level,
                        progress = FALSE
                    )

                    avg_acc <- NA
                    if (nrow(acc) > 0) {
                        avg_acc <- round(mean(acc$accessibility, na.rm = TRUE))
                    }

                    cat(paste(avg_acc, "\n"))

                    all_city_acc[[paste0(yr, "_", lts_level)]] <- data.frame(
                        city = city_lower,
                        year = as.integer(yr),
                        lts = lts_level,
                        access_15min_vol = avg_acc
                    )
                }

                # Stop engine to free JVM limits
                stop_r5()
                rJava::.jgc(R.gc = TRUE)
            },
            error = function(e) {
                cat(paste("  [ERROR] Accessibility failed for", city, yr, ":", e$message, "\n"))
            }
        )
    }

    # Update routing_summary.csv ONCE per city after all years are done
    if (length(all_city_acc) > 0) {
        summary_file <- file.path(city_dir, "routing_summary.csv")
        new_acc_df <- bind_rows(all_city_acc)

        if (!file.exists(summary_file)) {
            write.csv(new_acc_df, summary_file, row.names = FALSE)
        } else {
            # Load and consolidate existing summary
            existing_summary <- read.csv(summary_file) |>
                mutate(year = as.integer(year)) |>
                # Important: remove existing duplicates before merging
                distinct(city, year, lts, .keep_all = TRUE)

            # Prepare for clean merge: remove existing accessibility column if it exists
            if ("access_15min_vol" %in% names(existing_summary)) {
                existing_summary <- existing_summary |> select(-access_15min_vol)
            }

            # Join new data. Use left_join if we want to stick to rows with routing data,
            # or full_join if we want to preserve all results regardless.
            # Using full_join is safer to ensure no metadata is lost.
            updated_summary <- existing_summary |>
                full_join(new_acc_df, by = c("city", "year", "lts")) |>
                # Final sort for readability
                arrange(year, lts)

            write.csv(updated_summary, summary_file, row.names = FALSE)
            cat(paste("  Updated routing_summary.csv with accessibility results for", city, "\n"))
        }
    }
}

cat("Accessibility phase complete.\n")
