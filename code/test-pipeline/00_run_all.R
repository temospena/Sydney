# 00_run_all.R
# Master script to run the entire historical CI pipeline sequentially

# Load configuration to get target_cities
source("code/test-pipeline/config.R")

cat("==========================================\n")
cat("Starting Master CI Analysis Pipeline\n")
cat("Target Cities:", paste(target_cities, collapse = ", "), "\n")
cat("==========================================\n\n")

# List of steps in sequence
pipeline_steps <- c(
  "code/test-pipeline/01_od_data.R",
  "code/test-pipeline/02b_ci_osmactive.R",
  "code/test-pipeline/03_r5r_routing.R",
  "code/test-pipeline/04_analysis.R",
  "code/test-pipeline/05_final_metrics.R",
  "code/test-pipeline/07_plot_metrics.R",
  "code/test-pipeline/08_ci_maps.R"
  # 06_tidy_up.R is omitted from the master by default to allow review 
  # of intermediate RDS files if needed. Run it manually at the end.
)

for (step in pipeline_steps) {
  cat("------------------------------------------\n")
  cat("RUNNING STEP:", step, "\n")
  cat("------------------------------------------\n")
  
  tryCatch({
    source(step)
    cat("DONE STEP:", step, "\n\n")
  }, error = function(e) {
    cat("ERROR in STEP:", step, "\n")
    print(e)
    cat("Stopping pipeline execution.\n")
    stop()
  })
}

cat("==========================================\n")
cat("Master Pipeline Execution Complete!\n")
cat("==========================================\n")
