# update_ci_metrics.R
# Standalone script to re-run ONLY the parts related to CI metric estimations
# after modifying the 04_ci_osmactive.R tag parsing logic.
# Run this from the root project directory (e.g. source("code/pipeline/test-code/update_ci_metrics.R"))

# Load global configuration
source("code/pipeline/config.R")
library(tidyverse)
library(sf)

cat("==============================================================\n")
cat("1. Re-running 04_ci_osmactive.R to update Geometries\n")
cat("==============================================================\n")
FORCE_RERUN <<- FALSE

# Restore config state just in case
source("code/pipeline/config.R")

cat("==============================================================\n")
cat("2. Updating CI metrics in final_city_estimations.csv\n")
cat("==============================================================\n")

out_csv <- file.path(data_dir, "final_city_estimations.csv")
if (!file.exists(out_csv)) {
    stop("No final_city_estimations.csv found!")
}

final_df <- read.csv(out_csv)
final_df$year <- as.character(final_df$year) # Ensure year is character for string matching


cat("==============================================================\n")
cat("3. Plotting only CI types and CI Spatial Maps\n")
cat("==============================================================\n")

library(ggplot2)
library(tmap)
years_labels <- paste0("20", years)

for (current_city in unique(final_df$city)) {
    if (!(tolower(current_city) %in% tolower(target_cities))) next
    city_lower <- tolower(current_city)
    results_dir <- file.path(data_dir, city_lower, "results")
    dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

    city_df <- final_df |> filter(tolower(city) == city_lower)

    # --- 2. Maps (CI facet map only) ---
    all_ci_list <- list()
    for (i in seq_along(versions)) {
        v <- versions[i]
        yr <- years_labels[i]
        ci_path <- file.path(data_dir, city_lower, paste0(city_lower, "_ci_osmactive_", v, ".gpkg"))
        if (file.exists(ci_path)) {
            ci_layer <- st_read(ci_path, quiet = TRUE) |>
                mutate(year = yr) |>
                select(any_of(c("infra5", "year")))
            all_ci_list[[yr]] <- ci_layer
        }
    }

    if (length(all_ci_list) > 0) {
        all_ci <- bind_rows(all_ci_list) |>
            mutate(year = factor(year, levels = years_labels)) |>
          arrange(year, infra5)
            # arrange(year, desc(infra5))
        tmap_mode("plot")

        perim_path <- file.path(data_dir, city_lower, paste0(city_lower, "_10km.gpkg"))
        perim <- if (file.exists(perim_path)) st_read(perim_path, quiet = TRUE) else NULL

        map_obj <- tm_shape(all_ci) +
            tm_lines(col = "infra5", col.scale = tm_scale_categorical(values = ci_colors), lwd = 1.5, col.legend = tm_legend(title = "Infrastructure Type")) +
            tm_facets(by = "year", ncol = 3, sync = TRUE, free.coords = FALSE) +
            tm_title(paste(current_city, "- Cycling Infrastructure Evolution")) +
            tm_layout(legend.outside = TRUE, legend.outside.position = "bottom", frame = FALSE, legend.reverse = TRUE)

        if (!is.null(perim)) map_obj <- tm_shape(perim) + tm_borders(col_alpha = 0.2) + map_obj

        tmap_save(map_obj, file.path(results_dir, "ci_evolution_facet_map.png"), width = 15, height = 7)
        cat("  Generated CI facet map for", current_city, "\n")
    }
}

cat("==============================================================\n")
cat("CI Metric update successfully completed!\n")
cat("==============================================================\n")
