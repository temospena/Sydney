# 09b_plot_metrics_novoverline.R
# Generate requested stacked horizontal bars analyzing CI land use and actual routing habits

library(tidyverse)
library(ggplot2)

# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run
metrics_file <- file.path(data_dir, "final_city_estimations.csv")

if (!file.exists(metrics_file)) {
  stop("Metrics file not found. Run 05_final_metrics.R first.")
}

final_df <- read.csv(metrics_file) |>
  filter(city %in% target_cities)

for (current_city in unique(final_df$city)) {
  city_lower <- tolower(current_city)
  results_dir <- file.path(data_dir, city_lower, "results")
  dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

  city_df <- final_df |> filter(city == current_city)

  # 1. Plot: stacked horizontal bar (x5 years) for the pct of LTS used for the routes.
  for (lts_val in lts_levels) {
    lts_routes <- city_df |>
      filter(lts == lts_val)
    if (nrow(lts_routes) == 0) next

    lts_routes_long <- lts_routes |>
      select(year, pct_lts1, pct_lts2, pct_lts3, pct_lts4) |>
      pivot_longer(-year, names_to = "LTS", values_to = "pct") |>
      mutate(LTS = str_replace(LTS, "pct_", "")) |>
      mutate(year = as.factor(year))

    p1 <- ggplot(lts_routes_long, aes(y = fct_rev(year), x = pct, fill = LTS)) +
      geom_bar(stat = "identity", position = "stack") +
      scale_fill_viridis_d(option = "cividis", direction = -1) +
      labs(
        title = paste(current_city, "- Route Usage by LTS (Original)"),
        subtitle = paste("Percentage of LTS road types driven on routes (LTS", lts_val, "max)"),
        x = "Percentage (%)",
        y = "Year",
        fill = "Network LTS Level"
      ) +
      theme_minimal()

    ggsave(file.path(results_dir, paste0("plot_route_lts_usage_lts", lts_val, ".png")), p1, width = 8, height = 4)

    # 1b. Plot: stacked horizontal bar for the pct of LTS used for the routes (alternative)
    if ("pct_lts1_alternative" %in% names(city_df)) {
      lts_routes_alt <- lts_routes |>
        select(year, pct_lts1_alternative, pct_lts2_alternative, pct_lts3_alternative, pct_lts4_alternative) |>
        pivot_longer(-year, names_to = "LTS", values_to = "pct") |>
        mutate(LTS = str_replace(LTS, "pct_(lts[1-4])_alternative", "\\1")) |>
        mutate(year = as.factor(year))

      p1b <- ggplot(lts_routes_alt, aes(y = fct_rev(year), x = pct, fill = LTS)) +
        geom_bar(stat = "identity", position = "stack") +
        scale_fill_viridis_d(option = "cividis", direction = -1) +
        labs(
          title = paste(current_city, "- Route Usage by LTS (Alternative)"),
          subtitle = paste0("Percentage of LTS road types driven on routes (LTS ", lts_val, " max, CI=1)"),
          x = "Percentage (%)",
          y = "Year",
          fill = "Network LTS Level"
        ) +
        theme_minimal()

      ggsave(file.path(results_dir, paste0("plot_route_lts_usage_alternative_lts", lts_val, ".png")), p1b, width = 8, height = 4)
    }
  }

  # 2. Plot: stacked horizontal bar for the pct of LTS in total regarding the existing road network.
  overall_lts <- city_df |>
    filter(lts == 1) |>
    select(year, pct_lts1_total, pct_lts2_total, pct_lts3_total, pct_lts4_total) |>
    pivot_longer(-year, names_to = "LTS", values_to = "pct") |>
    mutate(LTS = str_replace(LTS, "pct_(lts[1-4])_total", "\\1")) |>
    mutate(year = as.factor(year))

  p2 <- ggplot(overall_lts, aes(y = fct_rev(year), x = pct, fill = LTS)) +
    geom_bar(stat = "identity", position = "stack") +
    scale_fill_viridis_d(option = "cividis", direction = -1) +
    labs(
      title = paste(current_city, "- Existing Network LTS Breakdown"),
      subtitle = "Percentage of each LTS street limit out of total non-pedestrian roads",
      x = "Percentage (%)",
      y = "Year",
      fill = "Network LTS Level"
    ) +
    theme_minimal()

  ggsave(file.path(results_dir, "plot_existing_lts_breakdown.png"), p2, width = 8, height = 4)

  # 3. Plot: stacked horizontal bar for pct of CI by type
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

  # Create a percentage version manually for the pct plot
  ci_type_pct <- ci_type_abs |>
    group_by(year) |>
    mutate(pct = round(len_m / pmax(sum(len_m, na.rm = TRUE), 1) * 100, 2)) |>
    ungroup()

  p3 <- ggplot(ci_type_pct, aes(y = fct_rev(year), x = pct, fill = CI_Type)) +
    geom_bar(stat = "identity", position = "stack") +
    scale_fill_manual(values = ci_colors) +
    labs(
      title = paste(current_city, "- Cycling Infrastructure Evolution (Percentage)"),
      subtitle = "Percentage of total CI length split by Infrastructure Type",
      x = "Percentage (%)",
      y = "Year",
      fill = "CI Type"
    ) +
    theme_minimal()

  ggsave(file.path(results_dir, "plot_ci_types_breakdown.png"), p3, width = 8, height = 4)

  # 4. Plot: absolute stacked length of CI by type
  p4 <- ggplot(ci_type_abs, aes(y = fct_rev(year), x = len_m / 1000, fill = CI_Type)) +
    geom_bar(stat = "identity", position = "stack") +
    scale_fill_manual(values = ci_colors) +
    labs(
      title = paste(current_city, "- Cycling Infrastructure Evolution (Absolute Length)"),
      subtitle = "Total CI length split by Infrastructure Type",
      x = "Length (km)",
      y = "Year",
      fill = "CI Type"
    ) +
    theme_minimal()

  ggsave(file.path(results_dir, "plot_ci_types_absolute.png"), p4, width = 8, height = 4)

  # # 5. Overline Density Matrix (Grid of LTS vs Years)
  # cat("  Generating Overline Density Matrix...\n")
  # overlines_list <- list()
  # for (lts_level in 1:4) {
  #   ov_rds <- file.path(results_dir, paste0("overline_data_lts", lts_level, ".rds"))
  #   if (file.exists(ov_rds)) {
  #     ovline <- readRDS(ov_rds) |>
  #       mutate(lts = paste0("LTS ", lts_level)) |>
  #       filter(as.character(year) %in% c("2016", "2021", "2026")) |>
  #       st_simplify(dTolerance = 0.0001) # Simplify geometries before plotting
  #     overlines_list[[lts_level]] <- ovline
  #   }
  # }
  #
  # if (length(overlines_list) > 0) {
  #   all_overlines <- bind_rows(overlines_list) |>
  #     filter(trips > 1) |> # Basic filtering to keep it readable
  #     mutate(
  #       year = factor(year, levels = c("2016", "2021", "2026")),
  #       lts = factor(lts, levels = c("LTS 1", "LTS 2", "LTS 3", "LTS 4"))
  #     ) |>
  #     filter(!is.na(year)) # To drop any remaining uncategorized years
  #
  #   p_matrix <- ggplot() +
  #     geom_sf(data = all_overlines, aes(linewidth = trips, color = trips), key_glyph = "path") +
  #     scale_color_viridis_c(option = "inferno", direction = -1) +
  #     scale_linewidth_continuous(range = c(0.1, 2.5)) +
  #     facet_grid(lts ~ year, switch = "y") +
  #     theme_minimal() +
  #     theme(
  #       axis.text = element_blank(),
  #       axis.ticks = element_blank(),
  #       panel.grid = element_blank(),
  #       strip.placement = "outside",
  #       strip.text.y.left = element_text(angle = 90, size = 11, face = "bold"),
  #       strip.text.x = element_text(size = 11, face = "bold"),
  #       legend.position = "bottom",
  #       legend.direction = "horizontal",
  #       legend.key.width = unit(1.2, "cm")
  #     ) +
  #     labs(
  #       title = paste("Routing Density Matrix -", current_city),
  #       subtitle = "Comparative trip volumes across all LTS levels and infrastructure years",
  #       color = "Trip Volume",
  #       linewidth = "Trip Volume"
  #     )
  #
  #   ggsave(file.path(results_dir, "overline_density_matrix.png"), p_matrix, width = 10, height = 14, bg = "white")
  # }
}

cat("Phase 09b Plotting Metrics Completed!\n")
