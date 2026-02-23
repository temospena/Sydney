# 08_ci_maps.R
# Generate multi-year facet maps for custom cycling infrastructure

library(tidyverse)
library(sf)
library(tmap)

# Load global configuration
source("code/test-pipeline/config.R")
years_labels <- paste0("20", years)

cat("Starting Phase 08 CI Facet Mapping...\n")

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)
    results_dir <- file.path(city_dir, "results")
    dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

    all_ci_list <- list()
    for (i in seq_along(versions)) {
        v <- versions[i]
        yr <- years_labels[i]
        ci_path <- file.path(city_dir, paste0(city_lower, "_ci_osmactive_", v, ".gpkg"))
        
        if (file.exists(ci_path)) {
            ci_layer <- st_read(ci_path, quiet = TRUE) |>
                mutate(year = yr) |>
                select(any_of(c("infra5", "year")))
            all_ci_list[[yr]] <- ci_layer
        }
    }

    if (length(all_ci_list) == 0) {
        warning(paste("No CI layers found for", city))
        next
    }

    all_ci <- bind_rows(all_ci_list) |>
        mutate(year = factor(year, levels = years_labels))

    # Static plot mode
    tmap_mode("plot")
    
    # Load perimeter for clipping/boundary
    perim_path <- file.path(city_dir, paste0(city_lower, "_10km.gpkg"))
    if (file.exists(perim_path)) {
        perim <- st_read(perim_path, quiet = TRUE)
    } else {
        perim <- NULL
    }

    map_obj <- tm_shape(all_ci) +
        tm_lines(
            col = "infra5",
            col.scale = tm_scale_categorical(values = ci_colors),
            lwd = 1.5,
            col.legend = tm_legend(title = "Infrastructure Type")
        ) +
        tm_facets(by = "year", ncol = 3, sync = TRUE, free.coords = FALSE) +
        tm_title(paste(city, "- Cycling Infrastructure Evolution")) +
        tm_layout(
            legend.outside = TRUE,
            legend.outside.position = "bottom",
            frame = FALSE
        )

    if (!is.null(perim)) {
        map_obj <- tm_shape(perim) + tm_borders(col_alpha = 0.2) + map_obj
    }

    out_file <- file.path(results_dir, "ci_evolution_facet_map.png")
    tmap_save(map_obj, out_file, width = 15, height = 7)
    cat(paste("Successfully saved", out_file, "\n"))


    # Load and filter LTS data per year (filtering early is much faster)
    all_lts_list <- list()
    
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
            )

        lts_map_obj <- tm_shape(all_lts) +
            tm_lines(
                col = "bicycle_lts",
                col.scale = tm_scale_categorical(values = c("#26a65b", "#f9bf3b", "#d60700ff", "#502e89ff")),
                lwd = 0.8,
                col.legend = tm_legend(title = "LTS Level")
            ) +
            tm_facets(by = "year", ncol = 3, sync = TRUE, free.coords = FALSE) +
            tm_title(paste(city, "- Network LTS Level Evolution")) +
            tm_layout(
                legend.outside = TRUE,
                legend.outside.position = "bottom",
                frame = FALSE
            )

        if (!is.null(perim)) {
            lts_map_obj <- tm_shape(perim) + tm_borders(col_alpha = 0.1) + lts_map_obj
        }

        out_lts_file <- file.path(results_dir, "lts_evolution_facet_map.png")
        tmap_save(lts_map_obj, out_lts_file, width = 15, height = 7)
        cat(paste("Successfully saved", out_lts_file, "\n"))
    }
}

cat("Phase 08 completed.\n")
