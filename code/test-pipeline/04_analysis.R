# 04_analysis.R
# Analyze routing results: distances, circuity, and visualizations

library(tidyverse)
library(sf)
library(stplanr)
library(tmap)
library(ggplot2)

data_dir <- "~/GIS/Sydney/data/test-pipeline"
target_cities <- c("Lisbon", "Sydney", "Paris", "Barcelona")
years <- c("16", "21", "26")

cat("Starting Phase 3 Analysis...\n")

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)
    results_dir <- file.path(city_dir, "results")
    dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

    cat(paste("Processing analysis for", city, "\n"))

    # Only parsing LTS 2 and LTS 3 for general analysis as they are standard indicators
    # Feel free to extend to LTS 1 and LTS 4
    for (lts_level in 2:3) {
        cat(paste("  Analyzing LTS", lts_level, "\n"))

        trips_list <- list()
        for (yr in years) {
            res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
            if (file.exists(res_file)) {
                trips_list[[yr]] <- readRDS(res_file) |> mutate(year = paste0("20", yr))
            }
        }

        if (length(trips_list) < 2) {
            cat("    Not enough years available to run comparisons. Skipping...\n")
            next
        }

        # Combine all
        trips_combined <- bind_rows(trips_list) |> mutate(year = as.factor(year))
        trips_df <- trips_combined |> st_drop_geometry()

        # 1. Plot Cumulative Travel Distance
        p1 <- ggplot(trips_df, aes(x = distance, color = year)) +
            stat_ecdf(lwd = 1.2) +
            geom_vline(xintercept = 5000, linetype = "dashed", color = "gray40") +
            annotate("text", x = 5400, y = 0.87, label = "5 km threshold", angle = 90) +
            scale_color_viridis_d() +
            labs(
                title = paste(city, "- Cumulative Travel Distance Distribution (LTS", lts_level, ")"),
                x = "Distance (meters)", y = "Proportion of all trips"
            ) +
            theme_minimal() +
            xlim(0, 20000)

        ggsave(file.path(results_dir, paste0("cumulative_distance_lts", lts_level, ".png")), p1, width = 8, height = 6)

        # 2. Distance differences (requires from_id, to_id, total_distance)
        trips_wide <- trips_df |>
            select(from_id, to_id, total_distance, year) |>
            pivot_wider(values_from = total_distance, names_from = year, names_prefix = "dist_")

        if ("dist_2016" %in% names(trips_wide) && "dist_2026" %in% names(trips_wide)) {
            p2 <- ggplot(trips_wide, aes(x = dist_2016, y = dist_2026)) +
                geom_point(alpha = 0.1, color = "midnightblue") +
                geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed") +
                geom_smooth(method = "lm", color = "green") +
                labs(
                    title = paste(city, "OD Distance: 2016 vs. 2026 (LTS", lts_level, ")"),
                    subtitle = "Points below the red line represent improved routing efficiency",
                    x = "Original Distance 2016 (m)", y = "Projected Distance 2026 (m)"
                ) +
                theme_minimal()

            ggsave(file.path(results_dir, paste0("distance_comparison_16_26_lts", lts_level, ".png")), p2, width = 8, height = 6)

            # Final CSV export with comparison
            trips_wide <- trips_wide |>
                mutate(
                    diff_1626 = dist_2026 - dist_2016,
                    change_pct = (dist_2026 - dist_2016) / dist_2016
                )

            write.csv(trips_wide, file.path(results_dir, paste0("routing_differences_lts", lts_level, ".csv")), row.names = FALSE)
        }

        # 3. Spatial overline generation for segment volume
        cat("    Generating overline map (this may take a while)...\n")
        trips_overline <- trips_combined |> mutate(trips = 1)

        map_data <- trips_overline |>
            group_split(year) |>
            map_dfr(function(year_data) {
                # Only overline to save size if there are actual geometries
                if (nrow(year_data) > 0) {
                    overline2(year_data, attrib = "trips") |> mutate(year = unique(year_data$year))
                } else {
                    NULL
                }
            }) |>
            filter(trips > 1) # Filter singlets for cleaner map

        # Plot tmap
        # tmap v4 format
        tmap_mode("plot")
        map_obj <- tm_shape(map_data) +
            tm_lines(
                col = "year",
                lwd = "trips",
                scale = 5,
                palette = "Set1",
                title.lwd = "Number of Trips\n(LTS2)"
            ) +
            tm_facets(by = "year", sync = TRUE, free.coords = FALSE)

        tmap_save(map_obj, file.path(results_dir, paste0("overline_map_lts", lts_level, ".png")), width = 12, height = 8)

        # Save network `.rds` for advanced interactive loading, then wipe the heavy files!
        saveRDS(map_data, file.path(results_dir, paste0("overline_map_data_lts", lts_level, ".rds")))

        rm(trips_list, trips_combined, trips_df, trips_wide, trips_overline, map_data, map_obj, p1)
        gc()
    }
}

cat("Analysis Phase Complete. All metrics and plots saved.\n")
