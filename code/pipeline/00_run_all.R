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
  "code/pipeline/01b_od_data.R",
  "code/pipeline/02_historical_routing_osm.R",
  "code/pipeline/02b_ci_osmactive.R",
  "code/pipeline/03_r5r_routing.R",
  "code/pipeline/04_analysis.R",
  "code/pipeline/05_final_metrics.R",
  "code/pipeline/07_plot_metrics.R",
  "code/pipeline/08_ci_maps.R",
  "code/pipeline/06_tidy_up.R"
)

# Run the pipeline for one city at a time
for (city_name in all_cities) {
  cat("\n******************************************\n")
  cat("PROCESSING CITY:", city_name, "\n")
  cat("******************************************\n\n")

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
}

cat("==========================================\n")
cat("Master Pipeline Execution Complete!\n")
cat("==========================================\n")
