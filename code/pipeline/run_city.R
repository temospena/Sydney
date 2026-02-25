# run_city.R
# Wrapper to run the full pipeline (Steps 01-11) for a specific city.
# Usage: Rscript code/pipeline/run_city.R "Munich"

# 1. Capture command line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
    # If no argument, load target_cities from config.R as a fallback
    source("code/pipeline/config.R")
    # Use the first one if we need a default, or just prompt
    if (!exists("target_cities") || length(target_cities) == 0) {
        stop("No city provided and no target_cities found in config.R")
    }
    cities_to_process <- target_cities
} else {
    cities_to_process <- args
}

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
    "code/pipeline/10_ci_maps.R",
    "code/pipeline/11_tidy_up.R"
)

cat("==========================================\n")
cat("City-by-City Pipeline Runner\n")
cat("Target Cities:", paste(cities_to_process, collapse = ", "), "\n")
cat("==========================================\n\n")

for (city_name in cities_to_process) {
    cat("\n******************************************\n")
    cat("STARTING FULL PIPELINE FOR:", toupper(city_name), "\n")
    cat("******************************************\n\n")

    # Setting this variable allows all individual scripts to target ONLY this city
    city_to_run <- city_name

    for (step in pipeline_steps) {
        cat("------------------------------------------\n")
        cat("CITY:", city_name, "| STEP:", step, "\n")
        cat("------------------------------------------\n")

        if (!file.exists(step)) {
            cat("  [ERROR] Script not found:", step, "\n")
            next
        }

        tryCatch(
            {
                # Sourcing in the global environment ensures variables like city_to_run are respected
                source(step, local = FALSE)
                cat("\n[SUCCESS] Completed:", step, "\n\n")
            },
            error = function(e) {
                cat("\n[CRITICAL ERROR] in STEP:", step, "for CITY:", city_name, "\n")
                print(e)
                cat("\nStopping pipeline for", city_name, "due to error.\n")
                # We break the step loop but can continue to the next city if desired.
                # However, usually better to stop and investigate.
                return()
            }
        )

        # Force a garbage collection between steps to keep RAM low
        gc()
    }

    cat("\n******************************************\n")
    cat("COMPLETED FULL PIPELINE FOR:", toupper(city_name), "\n")
    cat("******************************************\n\n")
}

cat("==========================================\n")
cat("All requested cities processed.\n")
cat("==========================================\n")
