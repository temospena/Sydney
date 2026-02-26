# update_ci_metrics.R
# Standalone script to re-run only the parts related to CI metric estimations
# after modifying the 04_ci_osmactive.R tag parsing logic.
# Run this from the root project directory (e.g. source("code/pipeline/test-code/update_ci_metrics.R"))

# Load global configuration
source("code/pipeline/config.R")

cat("==============================================================\n")
cat("Starting CI metrics update for already processed cities...\n")
cat("Target cities: ", paste(target_cities, collapse = ", "), "\n")
cat("==============================================================\n")

# 1. Rerun 04_ci_osmactive.R to update the CI extraction logic
# We set FORCE_RERUN to TRUE temporarily so it overwrites the existing GPKGs
cat("\n--- Running 04_ci_osmactive.R ---\n")
FORCE_RERUN <<- TRUE
source("code/pipeline/04_ci_osmactive.R", local = TRUE)

# Put FORCE_RERUN back to its original state (defined in config.R, usually FALSE)
source("code/pipeline/config.R")

# 2. Rerun 08_final_metrics.R
# This will read the updated CI GPKGs, extract the new route usage stats,
# and safely append/replace them in final_city_estimations.csv
cat("\n--- Running 08_final_metrics.R ---\n")
source("code/pipeline/08_final_metrics.R", local = TRUE)

# 3. Rerun 09_plot_metrics.R
# This will generate the updated stacked charts.
cat("\n--- Running 09_plot_metrics.R ---\n")
source("code/pipeline/09_plot_metrics.R", local = TRUE)

# 4. Rerun 10_ci_maps.R
# This will update the spatial maps of the cycling infrastructure.
cat("\n--- Running 10_ci_maps.R ---\n")
source("code/pipeline/10_ci_maps.R", local = TRUE)

cat("==============================================================\n")
cat("CI Metric update successfully completed!\n")
cat("==============================================================\n")
