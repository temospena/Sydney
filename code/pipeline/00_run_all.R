# Master script to run the entire historical CI pipeline city by city

# Load configuration to get target_cities
source("code/pipeline/config.R")

cat("==========================================\n")
cat("Starting Master CI Analysis Pipeline\n")
cat("Target Cities:", paste(target_cities, collapse = ", "), "\n")
cat("==========================================\n\n")

# Snapshot the cities to process
all_cities <- target_cities

# List of steps in sequence
pipeline_steps <- c(
  "code/pipeline/01_city_buffers.R",
  "code/pipeline/02_od_data.R",
  "code/pipeline/03_historical_routing_osm.R",
  "code/pipeline/04_ci_osmactive.R",
  "code/pipeline/05_r5r_routing.R",
  "code/pipeline/06_accessibility.R",
  "code/pipeline/07_analysis.R",
  "code/pipeline/08_final_metrics.R",
  "code/pipeline/09_plot_metrics.R",
  "code/pipeline/10_ci_maps.R"
  # "code/pipeline/11_tidy_up.R"
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
  try(
    {
      if (requireNamespace("dplyr", quietly = TRUE)) {
        library(dplyr)
        csv_path <- file.path(data_dir, "final_city_estimations.csv")
        if (file.exists(csv_path) && exists("current_timestamp")) {
          cat("[TIMER] Updating final_city_estimations.csv with processing time...\n")
          df <- read.csv(csv_path)
          # Update only the rows from the current run
          df <- df %>%
            mutate(processing_time_minutes = if_else(
              city == city_name & run_timestamp == current_timestamp,
              round(duration_mins, 2),
              as.numeric(processing_time_minutes)
            ))
          write.csv(df, csv_path, row.names = FALSE)

          # Also update the individual city results file (archived version)
          city_results_dir <- file.path(data_dir, tolower(city_name), "results")
          local_csv <- file.path(city_results_dir, paste0("estimations_", current_timestamp, ".csv"))
          if (file.exists(local_csv)) {
            local_df <- read.csv(local_csv) %>%
              mutate(processing_time_minutes = round(duration_mins, 2))
            write.csv(local_df, local_csv, row.names = FALSE)
          }
        }
      }
    },
    silent = TRUE
  )
}

cat("==========================================\n")
cat("Master Pipeline Execution Complete!\n")
cat("==========================================\n")
