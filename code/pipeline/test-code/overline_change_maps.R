# 10b_overline_change_maps.R
# Generate maps showing absolute changes in trip volumes between years
# Uses H3 grid aggregation for robustness against network topology changes.

## Tested only with Munich - did not provide nice outputs

library(tidyverse)
library(sf)
library(h3jsr)
library(stplanr)
library(ggplot2)
library(tmap)

# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run

cat("Starting 10b Overline Change Maps...\n")

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)
    results_dir <- file.path(city_dir, "results")
    dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

    cat(paste("Processing analysis for", city, "\n"))

    for (lts_level in lts_levels) {
        cat(paste("  LTS level:", lts_level, "\n"))

        ov_file <- file.path(results_dir, paste0("overline_data_lts", lts_level, ".rds"))

        map_data <- NULL
        if (file.exists(ov_file)) {
            cat("    Loading existing overline data...\n")
            map_data <- readRDS(ov_file)
        } else {
            cat("    Overline data not found. Attempting to generate from trips_*.rds...\n")

            trips_list <- list()
            for (yr in years) {
                res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
                res_file_long <- file.path(city_dir, paste0("trips_", city_lower, "_20", yr, "_lts", lts_level, ".rds"))

                trips_to_read <- NULL
                if (file.exists(res_file)) {
                    trips_to_read <- res_file
                } else if (file.exists(res_file_long)) trips_to_read <- res_file_long

                if (!is.null(trips_to_read)) {
                    trips_list[[yr]] <- readRDS(trips_to_read) |> mutate(year = paste0("20", yr))
                }
            }

            if (length(trips_list) >= 2) {
                trips_combined <- bind_rows(trips_list)
                trips_overline <- trips_combined |>
                    mutate(trips = 1) |>
                    st_zm(drop = TRUE, what = "ZM") |>
                    st_simplify(dTolerance = 0.0002, preserveTopology = TRUE) |>
                    st_make_valid() |>
                    filter(!st_is_empty(geometry))

                map_data <- trips_overline |>
                    group_split(year) |>
                    map_dfr(function(year_data) {
                        yr_val <- unique(year_data$year)
                        year_data <- st_cast(year_data, "LINESTRING", warn = FALSE)
                        tryCatch(
                            {
                                ov <- overline2(year_data, attrib = "trips")
                                if (!is.null(ov)) ov |> mutate(year = yr_val) else NULL
                            },
                            error = function(e) NULL
                        )
                    })

                if (!is.null(map_data)) {
                    saveRDS(map_data, ov_file)
                }
            }
        }

        if (is.null(map_data) || nrow(map_data) == 0) {
            cat("    [SKIP] No overline data available for LTS", lts_level, "\n")
            next
        }

        # 2. Map trips to H3 grid
        cat("    Mapping trips to H3 grid (Resolution", h3_res - 1, "for visualization)...\n")
        plot_res <- h3_res - 1

        h3_results <- map_data |>
            mutate(h3_addr = point_to_cell(st_centroid(geometry), res = plot_res)) |>
            st_drop_geometry() |>
            group_by(year, h3_addr) |>
            summarise(trips = sum(trips, na.rm = TRUE), .groups = "drop")

        # 3. Pivot wider to calculate changes
        h3_wide <- h3_results |>
            pivot_wider(names_from = year, values_from = trips, names_prefix = "trips_", values_fill = 0)

        # 4. Identify comparison pairs
        available_years <- sort(unique(map_data$year))
        plot_pairs <- list()
        if ("2016" %in% available_years && "2021" %in% available_years) plot_pairs[["2016_2021"]] <- c("trips_2016", "trips_2021")
        if ("2021" %in% available_years && "2026" %in% available_years) plot_pairs[["2021_2026"]] <- c("trips_2021", "trips_2026")
        if ("2016" %in% available_years && "2026" %in% available_years) plot_pairs[["2016_2026"]] <- c("trips_2016", "trips_2026")

        if (length(plot_pairs) == 0) {
            cat("    [SKIP] Not enough years for comparison.\n")
            next
        }

        for (pair_name in names(plot_pairs)) {
            cols <- plot_pairs[[pair_name]]
            cat(paste("    Generating change maps for", pair_name, "...\n"))

            yr_start <- gsub("trips_", "", cols[1])
            yr_end <- gsub("trips_", "", cols[2])

            # --- 1. H3 Grid Map ---
            h3_diff <- h3_wide |>
                mutate(
                    diff = .data[[cols[2]]] - .data[[cols[1]]],
                    pct_change = ifelse(.data[[cols[1]]] == 0, 100, (diff / .data[[cols[1]]]) * 100)
                ) |>
                filter(abs(diff) > 0)

            if (nrow(h3_diff) > 0) {
                h3_sf <- cell_to_polygon(h3_diff$h3_addr, simple = FALSE) |>
                    mutate(h3_addr = h3_diff$h3_addr) |>
                    left_join(h3_diff, by = "h3_addr")

                max_abs_diff_h3 <- max(abs(h3_sf$diff), na.rm = TRUE)

                p_h3 <- ggplot() +
                    geom_sf(data = h3_sf, aes(fill = diff), color = NA) +
                    scale_fill_distiller(palette = "RdBu", direction = 1, limit = c(-max_abs_diff_h3, max_abs_diff_h3), name = "Trip Change") +
                    labs(title = paste(city, "H3 Change", pair_name)) +
                    theme_minimal()

                ggsave(file.path(results_dir, paste0("trip_change_h3_", pair_name, "_lts", lts_level, ".png")), p_h3, width = 10, height = 8, bg = "white")
            }

            # --- 2. Segment-Level Map ---
            cat("      Calculating segment-level differences via spatial join...\n")
            data_start <- map_data |> filter(year == yr_start)
            data_end <- map_data |> filter(year == yr_end)

            if (nrow(data_start) > 0 && nrow(data_end) > 0) {
                data_end_centroids <- st_centroid(data_end)
                joined_indices <- st_nearest_feature(data_end_centroids, data_start)
                dists <- st_distance(data_end_centroids, data_start[joined_indices, ], by_element = TRUE)

                data_compare <- data_end |>
                    mutate(
                        trips_start = ifelse(as.numeric(dists) <= 15, data_start$trips[joined_indices], 0),
                        trips_end = trips,
                        diff = trips_end - trips_start
                    ) |>
                    filter(abs(diff) > 1)

                max_abs_diff_seg <- max(abs(data_compare$diff), na.rm = TRUE)
                tmap_mode("plot")

                m_seg <- tm_shape(data_compare |> st_simplify(dTolerance = 0.0001)) +
                    tm_lines(
                        col = "diff",
                        palette = "-RdBu",
                        midpoint = 0,
                        style = "cont",
                        lwd = "trips_end",
                        lwd.scale = tm_scale_continuous(values.scale = 3),
                        title.col = "Change in Trips",
                        title.lwd = "Total Capacity (End Year)"
                    ) +
                    tm_layout(
                        main.title = paste(city, "Segment-Level Change:", yr_start, "to", yr_end),
                        main.title.size = 1.2,
                        legend.outside = TRUE
                    )

                tmap_save(m_seg, file.path(results_dir, paste0("trip_change_segments_", pair_name, "_lts", lts_level, ".png")), width = 12, height = 8)

                # Significant changes only version
                m_sig <- tm_shape(data_compare |> filter(abs(diff) > 5) |> st_simplify(dTolerance = 0.0001)) +
                    tm_lines(
                        col = "diff",
                        palette = "-RdBu",
                        midpoint = 0,
                        lwd = 2,
                        title.col = "Significant Change (>5 trips)"
                    ) +
                    tm_layout(main.title = paste(city, "Significant Segment Changes"), main.title.size = 1.2)

                tmap_save(m_sig, file.path(results_dir, paste0("trip_change_segments_sig_", pair_name, "_lts", lts_level, ".png")), width = 12, height = 8)

                cat("      Segment maps saved.\n")
            }
        }
    }
}

cat("10b Overline Change Maps Completed!\n")
