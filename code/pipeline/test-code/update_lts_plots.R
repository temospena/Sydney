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
# Static plot mode
tmap_mode("plot")
years_labels <- paste0("20", years)

for (city in target_cities) {
city_lower <- tolower(city)
city_dir <- file.path(data_dir, city_lower)
results_dir <- file.path(city_dir, "results")
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

all_ci_list <- list()

for (current_city in unique(final_df$city)) {
    if (!(tolower(current_city) %in% tolower(target_cities))) next
    city_lower <- tolower(current_city)
    results_dir <- file.path(data_dir, city_lower, "results")
    dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

    city_df <- final_df |> filter(tolower(city) == city_lower)

    # Load and filter LTS data per year (filtering early is much faster)
    all_lts_list <- list()

    
    # Load perimeter for clipping/boundary
    perim_path <- file.path(city_dir, paste0(city_lower, "_10km.gpkg"))
    if (file.exists(perim_path)) {
      perim <- st_read(perim_path, quiet = TRUE)
    } else {
      perim <- NULL
    }
    # Simplify perim slightly for faster intersections (10m tolerance approx)
    perim_simple <- if (!is.null(perim)) st_simplify(perim, dTolerance = 0.0001) else NULL
    
    for (i in seq_along(years_labels)) {
      yr_short <- substring(years_labels[i], 3)
      yr_full <- years_labels[i]
      lts_path <- file.path(city_dir, paste0("r5r_", yr_short), paste0(city_lower, "_", yr_short, "_lts.gpkg"))
      
      if (file.exists(lts_path)) {
        cat("  Loading and filtering LTS for", yr_full, "...\n")
        lts_layer <- st_read(lts_path, quiet = TRUE)
        
        # Filter by perimeter if available
        if (!is.null(perim_simple)) {
          lts_layer <- st_filter(lts_layer, perim_simple)
        }
        
        lts_layer <- lts_layer |>
          mutate(year = yr_full) |>
          select(bicycle_lts, year)
        
        all_lts_list[[yr_full]] <- lts_layer
      }
    }
    
    if (length(all_lts_list) > 0) {
      all_lts <- bind_rows(all_lts_list) |>
        mutate(
          year = factor(year, levels = years_labels),
          bicycle_lts = as.factor(bicycle_lts)
        ) |> 
        arrange(year, bicycle_lts)
      
      lts_map_obj <- tm_shape(all_lts) +
        tm_lines(
          col = "bicycle_lts",
          col.scale = tm_scale_categorical(values = c("#26a65b", "#f9bf3b", "#d60700ff", "#502e89ff")),
          lwd = c(0.6,0.8,1.1,1.4),
          col.legend = tm_legend(title = "LTS Level")
        ) +
        tm_facets(by = "year", ncol = 3, sync = TRUE, free.coords = FALSE) +
        tm_title(paste(city, "- Network LTS Level Evolution")) +
        tm_layout(
          legend.outside = TRUE,
          legend.outside.position = "bottom",
          frame = FALSE
          # legend.reverse = TRUE
        )
      
      if (!is.null(perim)) {
        lts_map_obj <- tm_shape(perim) + tm_borders(col_alpha = 0.1) + lts_map_obj
      }
      
      out_lts_file <- file.path(results_dir, "lts_evolution_facet_map.png")
      tmap_save(lts_map_obj, out_lts_file, width = 15, height = 7)
      cat(paste("Successfully saved", out_lts_file, "\n"))
    }
} }

cat("==============================================================\n")
cat("CI Metric update successfully completed!\n")
cat("==============================================================\n")
