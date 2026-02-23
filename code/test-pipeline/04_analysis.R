# 04_analysis.R
# Analyze routing results: distances, circuity, and visualizations

library(tidyverse)
library(sf)
library(stplanr)
library(tmap)
library(ggplot2)

# Load global configuration
source("code/test-pipeline/config.R")

cat("Starting Phase 3 Analysis...\n")

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)
    results_dir <- file.path(city_dir, "results")
    dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

    cat(paste("Processing analysis for", city, "\n"))

    # Process analysis for LTS 1 to 4
    for (lts_level in 1:4) {
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

        # Calculate snapped linear distance and circuity directly from routing geometries
        cat("    Calculating linear snapped distances and circuity...\n")
        trips_combined <- trips_combined |>
            mutate(
                snapped_start = lwgeom::st_startpoint(geometry),
                snapped_end = lwgeom::st_endpoint(geometry),
                linear_distance = as.numeric(st_distance(snapped_start, snapped_end, by_element = TRUE)),
                circuity = total_distance / linear_distance
            ) |>
            select(-snapped_start, -snapped_end)

        trips_df <- trips_combined |> st_drop_geometry()

        # Discard OD pairs missing in at least one year
        n_years <- length(unique(trips_df$year))
        valid_ods <- trips_df |>
            count(from_id, to_id) |>
            filter(n == n_years)

        trips_df <- trips_df |> inner_join(valid_ods |> select(from_id, to_id), by = c("from_id", "to_id"))
        cat("    Filtered to", nrow(valid_ods), "OD pairs successfully routed across all years.\n")

        # 1. Plot Cumulative Travel Distance
        p1 <- ggplot(trips_df, aes(x = total_distance, color = year)) +
            stat_ecdf(lwd = 1.2) +
            geom_vline(xintercept = 5000, linetype = "dashed", color = "gray40") +
            annotate("text", x = 5400, y = 0.87, label = "5 km", angle = 90) +
            scale_color_viridis_d() +
            labs(
                title = paste(city, "- Cumulative Travel Distance Distribution (LTS", lts_level, ")"),
                x = "Distance (meters)", y = "Proportion of all trips"
            ) +
            theme_minimal() +
            xlim(0, 20000)

        ggsave(file.path(results_dir, paste0("cumulative_distance_lts", lts_level, ".png")), p1, width = 8, height = 6)

        # Plot Circuity
        p_circ <- ggplot(trips_df, aes(x = circuity, color = year)) +
            geom_density(lwd = 1) +
            scale_color_viridis_d() +
            labs(
                title = paste(city, "- Route Circuity Distribution (LTS", lts_level, ")"),
                x = "Circuity (Total Distance / Linear Distance)", y = "Density"
            ) +
            theme_minimal() +
            xlim(1, 3)

        ggsave(file.path(results_dir, paste0("circuity_density_lts", lts_level, ".png")), p_circ, width = 8, height = 6)

        # 2. Distance differences (requires from_id, to_id, total_distance)
        trips_wide <- trips_df |>
            select(from_id, to_id, total_distance, year) |>
            pivot_wider(values_from = total_distance, names_from = year, names_prefix = "dist_")

        plot_diff <- function(x_col, y_col, yr_x, yr_y) {
            if (x_col %in% names(trips_wide) && y_col %in% names(trips_wide)) {
                p <- ggplot(trips_wide, aes(x = .data[[x_col]], y = .data[[y_col]])) +
                    geom_point(alpha = 0.1, color = "midnightblue") +
                    geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed") +
                    geom_smooth(method = "lm", color = "green") +
                    labs(
                        title = paste(city, "OD Distance:", yr_x, "vs.", yr_y, "(LTS", lts_level, ")"),
                        subtitle = "Points below the red line represent improved routing efficiency",
                        x = paste("Distance", yr_x, "(m)"), y = paste("Distance", yr_y, "(m)")
                    ) +
                    theme_minimal()
                ggsave(file.path(results_dir, paste0("distance_comparison_", substring(yr_x, 3), "_", substring(yr_y, 3), "_lts", lts_level, ".png")), p, width = 8, height = 6)
            }
        }

        plot_diff("dist_2016", "dist_2021", "2016", "2021")
        plot_diff("dist_2021", "dist_2026", "2021", "2026")
        plot_diff("dist_2016", "dist_2026", "2016", "2026")

        # Final CSV export with comparison
        if ("dist_2016" %in% names(trips_wide) && "dist_2021" %in% names(trips_wide) && "dist_2026" %in% names(trips_wide)) {
            trips_wide <- trips_wide |>
                mutate(
                    diff_1621 = dist_2021 - dist_2016,
                    diff_2126 = dist_2026 - dist_2021,
                    diff_1626 = dist_2026 - dist_2016,
                    change_pct = (dist_2026 - dist_2016) / dist_2016
                )
                
            # Distribution of Trip Distance Changes Histogram
            gains_long <- trips_wide |>
              select(diff_1621, diff_2126) |>
              pivot_longer(everything(), names_to = "period", values_to = "diff") |>
              mutate(period = recode(period, 
                                     "diff_1621" = "2016 to 2021", 
                                     "diff_2126" = "2021 to 2026"))
            
            p_hist <- ggplot(gains_long, aes(x = diff, fill = period)) +
              geom_histogram(binwidth = 250, color = "white", alpha = 0.7, position = "identity") +
              geom_vline(xintercept = 0, linetype = "dashed", size = 1) +
              # annotate("text", x = -2500, y = 1500, label = "Efficiency Gain\n(Shorter Trips)", color = "darkgreen") +
              # annotate("text", x = 2500, y = 1500, label = "Efficiency Loss\n(Longer Trips)", color = "darkred") +
              scale_fill_manual(values = c("2016 to 2021" = "#3498db", "2021 to 2026" = "#e67e22")) +
              labs(title = paste(city, "- Distribution of Trip Distance Changes (LTS", lts_level, ")"),
                   subtitle = "Negative values indicate the new infrastructure allowed for shorter routes",
                   x = "Change in Distance (meters)",
                   y = "Number of OD Pairs") +
              theme_minimal() + 
              xlim(-3500, 3500) # Cutting off outliers for better visibility
              
            ggsave(file.path(results_dir, paste0("distance_change_histogram_lts", lts_level, ".png")), p_hist, width = 8, height = 6)
        }
        write.csv(trips_wide, file.path(results_dir, paste0("routing_differences_lts", lts_level, ".csv")), row.names = FALSE)

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
                col.scale = tm_scale_categorical(values = "Set1"),
                lwd = "trips",
                lwd.scale = tm_scale_continuous(values.scale = 5),
                lwd.legend = tm_legend(title = paste0("Number of Trips\n(LTS", lts_level, ")"))
            ) +
            tm_facets(by = "year", sync = TRUE, free.coords = FALSE)

        tmap_save(map_obj, file.path(results_dir, paste0("overline_map_lts", lts_level, ".png")), width = 12, height = 8)

        # Skip saving network `.rds` for advanced interactive loading to avoid filling up disk space
        # saveRDS(map_data, file.path(results_dir, paste0("overline_map_data_lts", lts_level, ".rds")))

        rm(trips_list, trips_combined, trips_df, trips_wide, trips_overline, map_data, map_obj, p1)
        gc()
    }
}

cat("Analysis Phase Complete. All metrics and plots saved.\n")
