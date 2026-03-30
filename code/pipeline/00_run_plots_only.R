# 00_run_plots_only.R
# Run only the plot and map generation steps
# Use this after routing and metrics are complete

source("code/pipeline/config.R")

cat("==========================================\n")
cat("Running Plots & Maps Only\n")
cat("Target Cities:", paste(target_cities, collapse = ", "), "\n")
cat("==========================================\n\n")

all_cities <- target_cities

plot_steps <- c(
    # "code/pipeline/07b_analysis_plots.R",
    # "code/pipeline/09_plot_metrics.R",
    "code/pipeline/09b_plot_metrics_nooverline.R",
    "code/pipeline/10c_od_hex_map.R"
    # "code/pipeline/10_ci_maps.R"
)

for (city_name in all_cities) {
    cat("\n******************************************\n")
    cat("PLOTTING CITY:", city_name, "\n")
    cat("******************************************\n\n")

    city_to_run <- city_name

    for (step in plot_steps) {
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
            }
        )
    }
}

cat("==========================================\n")
cat("Plots & Maps Generation Complete!\n")
cat("==========================================\n")
