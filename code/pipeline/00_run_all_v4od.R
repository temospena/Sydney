# 00_run_all_v4od.R
# Master script to run the pipeline with v2 OD sampling (lognormal distance decay)
# Years: 2016, 2019, 2021, 2024, 2026 | 20k trips | Plots/Maps disabled

# Load configuration to get target_cities
source("code/pipeline/config.R")

cat("==========================================\n")
cat("Starting Pipeline V4 (r5r + v2 OD sampling)\n")
cat("Target Cities:", paste(target_cities, collapse = ", "), "\n")
cat("Years:", paste0("20", years), "\n")
cat("OD Pairs:", n_od_pairs, "\n")
cat("==========================================\n\n")

# Snapshot the cities to process
all_cities <- target_cities

# Pipeline steps (NO plots or maps — run those separately with 00_run_plots_only.R)
# Note: Accessibility is computed inside 05_r5r_routing.R (reuses same r5r engine)
pipeline_steps <- c(
    "code/pipeline/01_city_buffers.R",
    "code/pipeline/02_od_data.R",
    "code/pipeline/03_historical_routing_osm.R",
    "code/pipeline/04_ci_osmactive.R",
    "code/pipeline/05_r5r_routing.R",
    "code/pipeline/07_analysis.R",
    "code/pipeline/08_final_metrics.R",
    "code/pipeline/11_tidy_up.R"
)

# Run the pipeline for one city at a time
for (city_name in all_cities) {
    cat("\n******************************************\n")
    cat("PROCESSING CITY:", city_name, "\n")
    cat("******************************************\n\n")

    # Start Timer for this city
    city_start_time <- Sys.time()

    # Set variable so scripts can identify the single city to process
    city_to_run <- city_name

    for (step in pipeline_steps) {
        cat("------------------------------------------\n")
        cat("CITY:", city_name, "| STEP:", step, "\n")
        cat("------------------------------------------\n")

        tryCatch(
            {
                source(step)
                cat("DONE STEP:", step, "\n\n")
            },
            error = function(e) {
                cat("ERROR in STEP:", step, "for CITY:", city_name, "\n")
                print(e)
                cat("Continuing to next city (or stopping if critical)...\n")
            }
        )
    }

    # Calculate Total Duration
    city_end_time <- Sys.time()
    duration_mins <- as.numeric(difftime(city_end_time, city_start_time, units = "mins"))
    cat(sprintf("\n[TIMER] Finished %s in %.2f minutes.\n", city_name, duration_mins))

    # Update final_city_estimations.csv with the actual processing time
    tryCatch(
        {
            csv_path <- file.path(data_dir, "final_city_estimations.csv")
            if (file.exists(csv_path) && exists("current_timestamp")) {
                cat("[TIMER] Updating final_city_estimations.csv with processing time...\n")
                df <- read.csv(csv_path, stringsAsFactors = FALSE)

                # Base R approach for safety and guaranteed scoping
                match_idx <- which(
                    tolower(trimws(df$city)) == tolower(trimws(city_name)) &
                        as.character(df$run_timestamp) == current_timestamp
                )

                if (length(match_idx) > 0) {
                    # Make sure the column is properly numeric
                    df$processing_time_minutes <- as.numeric(as.character(df$processing_time_minutes))
                    df$processing_time_minutes[match_idx] <- round(duration_mins, 2)
                    write.csv(df, csv_path, row.names = FALSE)
                    cat(sprintf("[TIMER] Updated internal timer for %d matching rows.\n", length(match_idx)))
                } else {
                    cat("[TIMER] No matching rows found to update in the final CSV.\n")
                }

                # Also update the individual city results file (archived version)
                city_results_dir <- file.path(data_dir, tolower(city_name), "results")
                local_csv <- file.path(city_results_dir, paste0("estimations_", current_timestamp, ".csv"))
                if (file.exists(local_csv)) {
                    local_df <- read.csv(local_csv, stringsAsFactors = FALSE)
                    local_df$processing_time_minutes <- round(duration_mins, 2)
                    write.csv(local_df, local_csv, row.names = FALSE)
                }
            }
        },
        error = function(e) {
            cat("[TIMER] Warning: Failed to write processing time:", e$message, "\n")
        }
    )
}

cat("==========================================\n")
cat("Pipeline V4 Complete!\n")
cat("Plots/Maps were skipped. Run 00_run_plots_only.R to generate them.\n")
cat("==========================================\n")
