# 08_plot_metrics.R
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

  # 1. Plot: stacked horizontal bar (x3 years) for the pct of LTS used for the routes.
  # Let's use max_LTS = 4 (as it allows all LTS levels to be fully explored safely)
  lts4_routes <- city_df |>
    filter(lts == 4) |>
    select(year, pct_lts1, pct_lts2, pct_lts3, pct_lts4) |>
    pivot_longer(-year, names_to = "LTS", values_to = "pct") |>
    mutate(LTS = str_replace(LTS, "pct_", "")) |>
    mutate(year = as.factor(year))

  p1 <- ggplot(lts4_routes, aes(y = fct_rev(year), x = pct, fill = LTS)) +
    geom_bar(stat = "identity", position = "stack") +
    scale_fill_viridis_d(option = "cividis", direction = -1) +
    labs(
      title = paste(current_city, "- Route Usage by LTS"),
      subtitle = "Percentage of LTS road types driven upon along recommended routes (LTS 4 max)",
      x = "Percentage (%)",
      y = "Year",
      fill = "Network LTS Level"
    ) +
    theme_minimal()

  ggsave(file.path(results_dir, "plot_route_lts_usage.png"), p1, width = 8, height = 4)

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
}

cat("Phase 07 Plotting Metrics Completed!\n")
