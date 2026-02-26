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
FORCE_RERUN <<- TRUE
source("code/pipeline/04_ci_osmactive.R", local = TRUE)

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

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)

    for (yr in years) {
        yr_full <- paste0("20", yr)
        cat("  Processing metrics for", city, "Year", yr_full, "\n")

        # 1. Load updated CI
        v_ext <- versions[which(years == yr)]
        ci_path <- file.path(city_dir, paste0(city_lower, "_ci_osmactive_", v_ext, ".gpkg"))

        ci <- NULL
        ci_osm_ids <- character(0)
        if (file.exists(ci_path)) {
            ci <- st_read(ci_path, quiet = TRUE)
            ci_osm_ids <- as.character(ci$osm_id)
        }

        # 2. Get total_road_m from edges
        r5r_dir <- file.path(city_dir, paste0("r5r_", yr))
        edges_path <- file.path(r5r_dir, paste0(city_lower, "_", yr, "_lts.gpkg"))
        edges <- NULL
        total_road_m <- 0
        if (file.exists(edges_path)) {
            edges <- tryCatch(
                {
                    st_read(edges_path, quiet = TRUE) |>
                        st_drop_geometry() |>
                        select(edge_index, osm_id, bicycle_lts, length, car, bicycle)
                },
                error = function(e) NULL
            )

            if (!is.null(edges)) {
                valid_edges <- edges |> filter(car == "TRUE" | bicycle == "TRUE")
                total_road_m <- sum(valid_edges$length, na.rm = TRUE)
                edges$osm_id <- as.character(edges$osm_id)
            }
        }

        # Calculate land-use CI stats
        total_ci_m_val <- 0
        pct_ci_total_val <- 0
        ci_type_sep_m_val <- 0
        ci_type_paint_m_val <- 0
        ci_type_mixed_m_val <- 0
        ci_type_foot_m_val <- 0

        if (!is.null(ci)) {
            ci_lengths <- as.numeric(st_length(ci))
            total_ci_m_val <- round(sum(ci_lengths, na.rm = TRUE))
            if (total_road_m > 0) {
                pct_ci_total_val <- round(total_ci_m_val / total_road_m * 100, 2)
            }

            if ("infra5" %in% names(ci)) {
                ci_types <- data.frame(infra5 = as.character(ci$infra5), len = ci_lengths) |>
                    group_by(infra5) |>
                    summarise(total_len = sum(len, na.rm = TRUE), .groups = "drop")

                get_ci_len <- function(type_names) {
                    val <- ci_types$total_len[ci_types$infra5 %in% type_names]
                    if (length(val) > 0) {
                        return(sum(val))
                    } else {
                        return(0)
                    }
                }
                ci_type_sep_m_val <- round(get_ci_len("Separated cycling infrastructure"), 0)
                ci_type_paint_m_val <- round(get_ci_len("Painted on-road cycle lane"), 0)
                ci_type_mixed_m_val <- round(get_ci_len("Mixed traffic (motor vehicles with light infra)"), 0)
                ci_type_foot_m_val <- round(get_ci_len("Cycling on pedestrian infrastructure"), 0)
            }
        }

        # Loop over LTS to re-calculate pct_ci_route based on pre-calculated itineraries
        for (lts_level in 1:4) {
            res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
            res_file_long <- file.path(city_dir, paste0("trips_", city_lower, "_20", yr, "_lts", lts_level, ".rds"))

            trips_to_read <- NULL
            if (file.exists(res_file)) {
                trips_to_read <- res_file
            } else if (file.exists(res_file_long)) trips_to_read <- res_file_long

            pct_ci_route_val <- NA
            if (!is.null(trips_to_read) && !is.null(edges) && length(ci_osm_ids) > 0) {
                trips <- readRDS(trips_to_read)
                if (inherits(trips, "sf")) trips <- st_drop_geometry(trips)

                if (nrow(trips) > 0) {
                    edge_list <- strsplit(as.character(trips$edge_id_list), ",")
                    route_edges <- data.frame(
                        row_idx = rep(1:nrow(trips), lengths(edge_list)),
                        edge_index = as.numeric(unlist(edge_list))
                    )
                    route_stats <- route_edges |>
                        left_join(edges, by = "edge_index") |>
                        group_by(row_idx) |>
                        summarise(
                            total_edge_len = sum(length, na.rm = TRUE),
                            ci_len = sum(length[osm_id %in% ci_osm_ids], na.rm = TRUE),
                            .groups = "drop"
                        )

                    final_trips <- trips |>
                        mutate(row_idx = row_number()) |>
                        left_join(route_stats, by = "row_idx") |>
                        mutate(pct_ci = ci_len / pmax(total_edge_len, 1))

                    pct_ci_route_val <- round(mean(final_trips$pct_ci, na.rm = TRUE) * 100, 2)
                }
            }

            # Inject back into final_df
            match_idx <- which(tolower(final_df$city) == city_lower & final_df$year == yr_full & final_df$lts == lts_level)
            if (length(match_idx) > 0) {
                final_df$total_ci_m[match_idx] <- total_ci_m_val
                final_df$pct_ci_total[match_idx] <- pct_ci_total_val
                final_df$ci_type_sep_m[match_idx] <- ci_type_sep_m_val
                final_df$ci_type_paint_m[match_idx] <- ci_type_paint_m_val
                final_df$ci_type_mixed_m[match_idx] <- ci_type_mixed_m_val
                final_df$ci_type_foot_m[match_idx] <- ci_type_foot_m_val

                if (!is.na(pct_ci_route_val)) {
                    final_df$pct_ci_route[match_idx] <- pct_ci_route_val
                }
            }
        }
    }
}

write.csv(final_df, out_csv, row.names = FALSE)
cat("Updated final_city_estimations.csv successfully!\n")

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

    # --- 1. Plots (Absolute and Relative CI Lengths) ---
    ci_type_abs <- city_df |>
        filter(lts == 1) |>
        select(year, ci_type_sep_m, ci_type_paint_m, ci_type_mixed_m, ci_type_foot_m) |>
        rename(
            `Separated cycling infrastructure` = ci_type_sep_m,
            `Painted on-road cycle lane` = ci_type_paint_m,
            `Mixed traffic (motor vehicles with light infra)` = ci_type_mixed_m,
            `Cycling on pedestrian infrastructure` = ci_type_foot_m
        ) |>
        pivot_longer(-year, names_to = "CI_Type", values_to = "len_m") |>
        mutate(year = as.factor(year))

    ci_type_pct <- ci_type_abs |>
        group_by(year) |>
        mutate(pct = round(len_m / pmax(sum(len_m, na.rm = TRUE), 1) * 100, 2)) |>
        ungroup()

    p3 <- ggplot(ci_type_pct, aes(y = fct_rev(year), x = pct, fill = CI_Type)) +
        geom_bar(stat = "identity", position = "stack") +
        scale_fill_manual(values = ci_colors) +
        labs(title = paste(current_city, "- Cycling Infrastructure Evolution (Percentage)"), subtitle = "Percentage of total CI length split by Infrastructure Type", x = "Percentage (%)", y = "Year", fill = "CI Type") +
        theme_minimal()
    ggsave(file.path(results_dir, "plot_ci_types_breakdown.png"), p3, width = 8, height = 4)

    p4 <- ggplot(ci_type_abs, aes(y = fct_rev(year), x = len_m / 1000, fill = CI_Type)) +
        geom_bar(stat = "identity", position = "stack") +
        scale_fill_manual(values = ci_colors) +
        labs(title = paste(current_city, "- Cycling Infrastructure Evolution (Absolute Length)"), subtitle = "Total CI length split by Infrastructure Type", x = "Length (km)", y = "Year", fill = "CI Type") +
        theme_minimal()
    ggsave(file.path(results_dir, "plot_ci_types_absolute.png"), p4, width = 8, height = 4)
    cat("  Generated CI bar plots for", current_city, "\n")

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
