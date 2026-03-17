# ci_types_stats.R
# ============================================================================
# Evidence statistics: yearly change in CI by protection level
#
# Are sharrows (weak/mixed-traffic CI) being added to COMPLETE the network,
# or to SUBSTITUTE protected / painted CI?
#
# Three CI protection levels (matching the 'infra5' classification):
#   - Protected  : Separated cycling infrastructure     (ci_type_sep_m)
#   - Paint      : Painted on-road cycle lane            (ci_type_paint_m)
#   - Sharrows   : Mixed traffic (motor vehicles / light infra) (ci_type_mixed_m)
#   - Foot       : Cycling on pedestrian infra           (ci_type_foot_m)
#
# Outputs (written to data/pipeline/results/):
#   1. ci_type_change_stats.csv   — per-city-period absolute & relative changes
#   2. Table: cross-city summary of mean annual km change per type
#   3. Plots:
#       a. Stacked area - total CI composition over time (all cities, median)
#       b. Lollipop / diverging bar - mean annual km change per type per period
#       c. Scatter - change in sharrows vs change in protected (per city-period)
#       d. Scatter - change in sharrows vs change in paint   (per city-period)
#       e. Ratio plot - sharrow share of new CI added each period
#       f. Network share (% of road network) per type over time
#
# Run from project root: source("code/pipeline/test-code/ci_types_stats.R")
# ============================================================================

library(tidyverse)
library(scales)
library(ggrepel)
library(knitr)        # for kable table output
library(kableExtra)   # nicer tables (optional, falls back gracefully)

# ---------------------------------------------------------------------------
# 0. Paths & config
# ---------------------------------------------------------------------------
proj_root <- here::here()
if (!grepl("media", proj_root) && grepl("media", getwd())) proj_root <- getwd()
data_dir  <- file.path(proj_root, "data/pipeline")
out_dir   <- file.path(proj_root, "images/ci_analysis")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# CI type labels (prettier than column names)
type_labels <- c(
  ci_type_sep_m   = "Protected (Separated)",
  ci_type_paint_m = "Painted lane",
  ci_type_mixed_m = "Sharrows (Mixed traffic)",
  ci_type_foot_m  = "Shared pedestrian infra"
)

# Protection-level colour palette
type_colors <- c(
  "Protected (Separated)"       = "#054d05",
  "Painted lane"                = "#1A7832",
  "Sharrows (Mixed traffic)"    = "#AFD4A0",
  "Shared pedestrian infra"     = "#ebc0d4"
)

# Years in the dataset
year_order <- c(2016, 2019, 2021, 2024, 2026)

# 50 cities
target_cities <- c(
    "Amsterdam", "Austin", "Barcelona", "Beijing", "Berlin", "Bogota",
    "Bologna", "Brussels", "Buenos Aires", "Cairo", "Cape Town",
    "Chicago", "Christchurch", "Curitiba", "Dublin", "Gent", "Glasgow",
    "Graz", "Hamburg", "Helsinki", "Hong Kong", "Kyoto", "Leeds",
    "Lisbon", "Ljubljana", "London", "Lyon", "Madrid", "Melbourne",
    "Mexico City", "Milan", "Minneapolis", "Montpellier", "Montréal",
    "Munich", "Nantes", "New York", "Oslo", "Paris", "Portland",
    "San Francisco", "Santiago", "Sao Paulo", "Seattle", "Seoul",
    "Seville", "Shanghai", "Stockholm", "Strasbourg", "Sydney", "Taipei",
    "Tokyo", "Turin", "Vancouver", "Vienna", "Warsaw", "Zurich"
)
cities_less_100k <- c("Cairo", "Cape Town", "Hong Kong")
cities_weired_tagging <- c("Lisbon", "Munich", "Ljubljana") # Strasbourg, Vancouver
cities_no_data <- c()
cities_no_10pct_growth <- c("Amsterdam", "Stockholm")
target_cities_clean <- setdiff(
    target_cities,
    c(
        cities_less_100k,
        cities_weired_tagging,
        cities_no_data,
        cities_no_10pct_growth
    )
)
length(target_cities_clean) # 50


# ---------------------------------------------------------------------------
# 1. Load data — use lts == 1 rows only (CI metrics are duplicated across lts)
# ---------------------------------------------------------------------------
df_raw <- read.csv(file.path(data_dir, "final_city_estimations.csv")) |>
  filter(lts == 1) |>
  filter(city %in% target_cities_clean) |>
  mutate(
    year       = as.integer(as.character(year)),
    total_ci_km    = total_ci_m    / 1000,
    sep_km         = ci_type_sep_m   / 1000,
    paint_km       = ci_type_paint_m / 1000,
    mixed_km       = ci_type_mixed_m / 1000,  # sharrows
    foot_km        = ci_type_foot_m  / 1000,
    road_km        = total_road_m    / 1000
  ) |>
  filter(year %in% year_order) |>
  arrange(city, year)

# ---------------------------------------------------------------------------
# 2. Compute PERIOD CHANGES per city (wide → long differences)
# ---------------------------------------------------------------------------
# Period labels: "2016→2019", "2019→2021", …
period_pairs <- data.frame(
  yr_from = c(2016, 2019, 2021, 2024),
  yr_to   = c(2019, 2021, 2024, 2026)
) |>
  mutate(period = paste0(yr_from, "→", yr_to),
         n_years = yr_to - yr_from)

df_changes <- purrr::map_dfr(seq_len(nrow(period_pairs)), function(i) {
  yf <- period_pairs$yr_from[i]
  yt <- period_pairs$yr_to[i]
  pd <- period_pairs$period[i]
  ny <- period_pairs$n_years[i]

  from <- df_raw |> filter(year == yf) |>
    select(city, road_km,
           sep_from   = sep_km,
           paint_from = paint_km,
           mixed_from = mixed_km,
           foot_from  = foot_km,
           total_from = total_ci_km)

  to <- df_raw |> filter(year == yt) |>
    select(city,
           sep_to   = sep_km,
           paint_to = paint_km,
           mixed_to = mixed_km,
           foot_to  = foot_km,
           total_to = total_ci_km)

  inner_join(from, to, by = "city") |>
    mutate(
      period  = pd,
      n_years = ny,
      yr_from = yf,
      yr_to   = yt,
      # absolute change (km)
      d_sep   = sep_to   - sep_from,
      d_paint = paint_to - paint_from,
      d_mixed = mixed_to - mixed_from,   # sharrows
      d_foot  = foot_to  - foot_from,
      d_total = total_to - total_from,
      # annualised (km / year)
      a_sep   = d_sep   / n_years,
      a_paint = d_paint / n_years,
      a_mixed = d_mixed / n_years,
      a_foot  = d_foot  / n_years,
      a_total = d_total / n_years,
      # share of NEW ci that is each type (only where total grew)
      new_total = pmax(d_total, 0.001),
      share_new_sep   = d_sep   / new_total,
      share_new_paint = d_paint / new_total,
      share_new_mixed = d_mixed / new_total,
      share_new_foot  = d_foot  / new_total,
      # % of road network at end of period
      pct_road_sep   = sep_to   / road_km * 100,
      pct_road_paint = paint_to / road_km * 100,
      pct_road_mixed = mixed_to / road_km * 100,
      pct_road_foot  = foot_to  / road_km * 100
    )
})

# Save change statistics table
write.csv(df_changes, file.path(out_dir, "ci_type_change_stats.csv"), row.names = FALSE)
cat("[ci_types_stats] Saved ci_type_change_stats.csv\n")

# ---------------------------------------------------------------------------
# 3. SUMMARY TABLE: mean annual km change per type, by period (all cities)
# ---------------------------------------------------------------------------
summary_tbl <- df_changes |>
  group_by(period) |>
  summarise(
    n_cities       = n(),
    `Protected (km/yr)`  = round(mean(a_sep,   na.rm = TRUE), 1),
    `Paint (km/yr)`      = round(mean(a_paint, na.rm = TRUE), 1),
    `Sharrows (km/yr)`   = round(mean(a_mixed, na.rm = TRUE), 1),
    `Foot/shared (km/yr)`= round(mean(a_foot,  na.rm = TRUE), 1),
    `Total CI (km/yr)`   = round(mean(a_total, na.rm = TRUE), 1),
    .groups = "drop"
  )

cat("\n=== Mean annualised CI change per type (km/yr, across cities) ===\n")
print(knitr::kable(summary_tbl, format = "simple", align = "lrrrrr"))
cat("\n")

# Save table as CSV too
write.csv(summary_tbl, file.path(out_dir, "ci_type_summary_table.csv"), row.names = FALSE)

# ---------------------------------------------------------------------------
# 4. Long format for composition plots
# ---------------------------------------------------------------------------
df_long <- df_raw |>
  select(city, year, road_km, sep_km, paint_km, mixed_km, foot_km, total_ci_km) |>
  pivot_longer(
    cols      = c(sep_km, paint_km, mixed_km, foot_km),
    names_to  = "type_col",
    values_to = "km"
  ) |>
  mutate(
    CI_Type = dplyr::recode(type_col,
      sep_km   = "Protected (Separated)",
      paint_km = "Painted lane",
      mixed_km = "Sharrows (Mixed traffic)",
      foot_km  = "Shared pedestrian infra"
    ),
    CI_Type = factor(CI_Type, levels = names(type_colors))
  )

# Median across cities per year × type
df_median <- df_long |>
  group_by(year, CI_Type) |>
  summarise(med_km = median(km, na.rm = TRUE), .groups = "drop")

# ---------------------------------------------------------------------------
# PLOT A: Stacked area — median CI composition over time (all cities)
# ---------------------------------------------------------------------------
p_area <- ggplot(df_median, aes(x = year, y = med_km, fill = CI_Type)) +
  geom_area(position = "stack", alpha = 0.85, colour = "white", linewidth = 0.3) +
  scale_fill_manual(values = type_colors) +
  scale_x_continuous(breaks = year_order) +
  scale_y_continuous(labels = label_comma()) +
  labs(
    title    = "Cycling Infrastructure Composition Over Time",
    subtitle = "Median across cities — stacked by protection level",
    x        = "Year",
    y        = "Median CI length (km)",
    fill     = "CI Type"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title    = element_text(face = "bold"),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

ggsave(file.path(out_dir, "ci_type_composition_area.png"), p_area,
       width = 10, height = 6, bg = "white")
cat("[ci_types_stats] Saved ci_type_composition_area.png\n")

# ---------------------------------------------------------------------------
# PLOT B: Mean annual change per type per period (faceted lollipop)
# ---------------------------------------------------------------------------
change_long <- df_changes |>
  group_by(period) |>
  summarise(
    `Protected (Separated)`     = mean(a_sep,   na.rm = TRUE),
    `Painted lane`              = mean(a_paint, na.rm = TRUE),
    `Sharrows (Mixed traffic)`  = mean(a_mixed, na.rm = TRUE),
    `Shared pedestrian infra`   = mean(a_foot,  na.rm = TRUE),
    .groups = "drop"
  ) |>
  pivot_longer(-period, names_to = "CI_Type", values_to = "mean_annual_km") |>
  mutate(
    CI_Type = factor(CI_Type, levels = names(type_colors)),
    period  = factor(period, levels = unique(period_pairs$period))
  )

p_lollipop <- ggplot(change_long,
                     aes(x = mean_annual_km, y = CI_Type, colour = CI_Type)) +
  geom_vline(xintercept = 0, colour = "grey60", linetype = "dashed") +
  geom_segment(aes(x = 0, xend = mean_annual_km, yend = CI_Type),
               linewidth = 1, alpha = 0.7) +
  geom_point(size = 4) +
  geom_text(aes(label = sprintf("%+.1f", mean_annual_km)),
            hjust = ifelse(change_long$mean_annual_km >= 0, -0.25, 1.15),
            size = 3.5) +
  facet_wrap(~period, ncol = 2) +
  scale_colour_manual(values = type_colors, guide = "none") +
  scale_x_continuous(labels = label_comma()) +
  labs(
    title    = "Mean Annual Change in CI by Type and Period",
    subtitle = "km/year added (positive) or removed (negative), averaged across cities",
    x        = "Mean annual km change",
    y        = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title   = element_text(face = "bold"),
    strip.text   = element_text(face = "bold"),
    panel.grid.major.y = element_blank(),
    panel.grid.minor   = element_blank()
  )

ggsave(file.path(out_dir, "ci_type_annual_change_lollipop.png"), p_lollipop,
       width = 12, height = 7, bg = "white")
cat("[ci_types_stats] Saved ci_type_annual_change_lollipop.png\n")

# ---------------------------------------------------------------------------
# PLOT C: Scatter — Δsharrows vs Δprotected, per city-period
#         (Are sharrows substituting or complementing protected infra?)
# ---------------------------------------------------------------------------
p_scatter_sep <- ggplot(df_changes,
                        aes(x = d_mixed, y = d_sep,
                            colour = period, label = city)) +
  geom_hline(yintercept = 0, colour = "grey60", linetype = "dashed") +
  geom_vline(xintercept = 0, colour = "grey60", linetype = "dashed") +
  # Quadrant annotations
  annotate("text", x = Inf,  y = Inf,
           label = "Both grow\n(complement)", hjust = 1.1, vjust = 1.2,
           size = 3, colour = "grey40", fontface = "italic") +
  annotate("text", x = Inf,  y = -Inf,
           label = "Sharrows ↑, Protected ↓\n(substitute?)", hjust = 1.05, vjust = -0.2,
           size = 3, colour = "grey40", fontface = "italic") +
  annotate("text", x = -Inf, y = Inf,
           label = "Sharrows ↓, Protected ↑\n(upgrade?)", hjust = -0.05, vjust = 1.2,
           size = 3, colour = "grey40", fontface = "italic") +
  geom_point(alpha = 0.7, size = 2.5) +
  geom_smooth(method = "lm", se = TRUE, colour = "black", alpha = 0.15,
              linewidth = 0.8, linetype = "solid") +
  geom_text_repel(size = 2.5, max.overlaps = 12, segment.alpha = 0.4) +
  scale_colour_brewer(palette = "Set2") +
  labs(
    title    = "Sharrows vs Protected CI change (by city and period)",
    subtitle = "Each point = one city × one period. Positive = km added, Negative = km removed",
    x        = "Change in Sharrows / Mixed traffic (km)",
    y        = "Change in Protected / Separated CI (km)",
    colour   = "Period"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

ggsave(file.path(out_dir, "ci_scatter_mixed_vs_separated.png"), p_scatter_sep,
       width = 12, height = 8, bg = "white")
cat("[ci_types_stats] Saved ci_scatter_mixed_vs_separated.png\n")

# ---------------------------------------------------------------------------
# PLOT D: Scatter — Δsharrows vs Δpaint
# ---------------------------------------------------------------------------
p_scatter_paint <- ggplot(df_changes,
                          aes(x = d_mixed, y = d_paint,
                              colour = period, label = city)) +
  geom_hline(yintercept = 0, colour = "grey60", linetype = "dashed") +
  geom_vline(xintercept = 0, colour = "grey60", linetype = "dashed") +
  annotate("text", x = Inf,  y = Inf,
           label = "Both grow\n(complement)", hjust = 1.1, vjust = 1.2,
           size = 3, colour = "grey40", fontface = "italic") +
  annotate("text", x = Inf,  y = -Inf,
           label = "Sharrows ↑, Paint ↓\n(substitute?)", hjust = 1.05, vjust = -0.2,
           size = 3, colour = "grey40", fontface = "italic") +
  annotate("text", x = -Inf, y = Inf,
           label = "Sharrows ↓, Paint ↑\n(upgrade?)", hjust = -0.05, vjust = 1.2,
           size = 3, colour = "grey40", fontface = "italic") +
  geom_point(alpha = 0.7, size = 2.5) +
  geom_smooth(method = "lm", se = TRUE, colour = "black", alpha = 0.15,
              linewidth = 0.8) +
  geom_text_repel(size = 2.5, max.overlaps = 12, segment.alpha = 0.4) +
  scale_colour_brewer(palette = "Set2") +
  labs(
    title    = "Sharrows vs Painted lane CI change (by city and period)",
    subtitle = "Each point = one city × one period. Positive = km added, Negative = km removed",
    x        = "Change in Sharrows / Mixed traffic (km)",
    y        = "Change in Painted lane CI (km)",
    colour   = "Period"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

ggsave(file.path(out_dir, "ci_scatter_mixed_vs_paint.png"), p_scatter_paint,
       width = 12, height = 8, bg = "white")
cat("[ci_types_stats] Saved ci_scatter_mixed_vs_paint.png\n")

# ---------------------------------------------------------------------------
# PLOT E: Sharrow share of NEWLY ADDED CI per period (across cities, boxplot)
#         Only for periods where total CI grew (d_total > 0)
# ---------------------------------------------------------------------------
share_new_long <- df_changes |>
  filter(d_total > 0) |>   # only cities/periods that actually added CI
  select(city, period, yr_from,
         `Protected (Separated)`     = share_new_sep,
         `Painted lane`              = share_new_paint,
         `Sharrows (Mixed traffic)`  = share_new_mixed,
         `Shared pedestrian infra`   = share_new_foot) |>
  pivot_longer(
    -c(city, period, yr_from),
    names_to  = "CI_Type",
    values_to = "share"
  ) |>
  mutate(
    CI_Type = factor(CI_Type, levels = names(type_colors)),
    period  = factor(period, levels = unique(period_pairs$period))
  ) |>
  # cap extreme values (>100% or <-50%) from rounding noise
  filter(share > -0.5, share < 1.5)

p_share <- ggplot(share_new_long,
                  aes(x = period, y = share * 100, fill = CI_Type)) +
  geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
  geom_boxplot(outlier.size = 1.2, alpha = 0.8, width = 0.6, notch = FALSE) +
  facet_wrap(~CI_Type, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = type_colors, guide = "none") +
  scale_y_continuous(labels = label_percent(scale = 1)) +
  labs(
    title    = "Share of newly added CI by type, across periods",
    subtitle = "% of total new CI (km) attributed to each type — only cities that grew",
    x        = "Period",
    y        = "Share of new CI (%)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold"),
    strip.text       = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    axis.text.x      = element_text(angle = 30, hjust = 1)
  )

ggsave(file.path(out_dir, "ci_share_new_boxplot.png"), p_share,
       width = 12, height = 8, bg = "white")
cat("[ci_types_stats] Saved ci_share_new_boxplot.png\n")

# ---------------------------------------------------------------------------
# PLOT F: % of road network per type over time (cross-city median)
# ---------------------------------------------------------------------------
net_share_long <- df_raw |>
  filter(road_km > 0) |>
  transmute(
    city, year,
    `Protected (Separated)`     = sep_km   / road_km * 100,
    `Painted lane`              = paint_km / road_km * 100,
    `Sharrows (Mixed traffic)`  = mixed_km / road_km * 100,
    `Shared pedestrian infra`   = foot_km  / road_km * 100
  ) |>
  pivot_longer(-c(city, year), names_to = "CI_Type", values_to = "pct") |>
  mutate(CI_Type = factor(CI_Type, levels = names(type_colors)))

net_share_med <- net_share_long |>
  group_by(year, CI_Type) |>
  summarise(
    med_pct = median(pct, na.rm = TRUE),
    q25     = quantile(pct, 0.25, na.rm = TRUE),
    q75     = quantile(pct, 0.75, na.rm = TRUE),
    .groups = "drop"
  )

p_netshare <- ggplot(net_share_med,
                     aes(x = year, y = med_pct, colour = CI_Type, fill = CI_Type)) +
  geom_ribbon(aes(ymin = q25, ymax = q75), alpha = 0.15, colour = NA) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  scale_colour_manual(values = type_colors) +
  scale_fill_manual(values = type_colors, guide = "none") +
  scale_x_continuous(breaks = year_order) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(
    title    = "CI as % of Road Network — by protection level",
    subtitle = "Median across cities (ribbon = IQR)",
    x        = "Year",
    y        = "CI length / road network length (%)",
    colour   = "CI Type"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title       = element_text(face = "bold"),
    legend.position  = "bottom",
    panel.grid.minor = element_blank()
  )

ggsave(file.path(out_dir, "ci_type_pct_road_network.png"), p_netshare,
       width = 11, height = 6, bg = "white")
cat("[ci_types_stats] Saved ci_type_pct_road_network.png\n")

# ---------------------------------------------------------------------------
# BONUS PLOT G: Per-city total CI composition (latest year vs earliest year)
#   Slope-chart: each CI type for each city, 2016 → 2026
# ---------------------------------------------------------------------------
slope_data <- df_raw |>
  filter(year %in% c(2016, 2026)) |>
  select(city, year, sep_km, paint_km, mixed_km) |>
  pivot_longer(c(sep_km, paint_km, mixed_km),
               names_to = "type_col", values_to = "km") |>
  mutate(
    CI_Type = dplyr::recode(type_col,
      sep_km   = "Protected (Separated)",
      paint_km = "Painted lane",
      mixed_km = "Sharrows (Mixed traffic)"
    ),
    CI_Type = factor(CI_Type, levels = names(type_colors)),
    year    = as.factor(year)
  )

p_slope <- ggplot(slope_data,
                  aes(x = year, y = km, group = interaction(city, CI_Type),
                      colour = CI_Type)) +
  geom_line(alpha = 0.35, linewidth = 0.7) +
  geom_point(alpha = 0.5, size = 1.5) +
  # Median line per type
  stat_summary(aes(group = CI_Type, colour = CI_Type),
               fun = median, geom = "line",
               linewidth = 2, alpha = 1) +
  stat_summary(aes(group = CI_Type, colour = CI_Type),
               fun = median, geom = "point",
               size = 5, alpha = 1) +
  facet_wrap(~CI_Type, scales = "free_y", ncol = 3) +
  scale_colour_manual(values = type_colors, guide = "none") +
  scale_y_continuous(labels = label_comma()) +
  labs(
    title    = "CI Length 2016 → 2026: Protected vs Painted vs Sharrows",
    subtitle = "Thin lines: individual cities | Thick line: cross-city median",
    x        = "Year",
    y        = "CI length (km)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold"),
    strip.text       = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

ggsave(file.path(out_dir, "ci_type_slope_2016_2026.png"), p_slope,
       width = 13, height = 6, bg = "white")
cat("[ci_types_stats] Saved ci_type_slope_2016_2026.png\n")

# ---------------------------------------------------------------------------
# 5. Substitution analysis — multiple methods
# ---------------------------------------------------------------------------
# KEY QUESTION: Are sharrows replacing protected / painted CI,
#               or growing independently?
# Methods used:
#   5a. All pairwise Pearson + Spearman correlations (absolute Δkm)
#   5b. Share-change correlations (compositional — removes city-size effect)
#   5c. Wilcoxon median-split test (cities with high vs low sharrow growth)
#   5d. OLS regression Δprotected ~ Δsharrows + Δtotal (controls for overall growth)
#   5e. Protection trajectory classification + plot
# ---------------------------------------------------------------------------

# --- 5a. All pairwise Pearson + Spearman correlations ---------------------
cat("\n================================================================\n")
cat("5a. Pairwise correlations (Pearson r | Spearman ρ) — all periods\n")
cat("================================================================\n")

pairs <- list(
  c("d_mixed", "d_sep",   "Δ Sharrows vs Δ Protected"),
  c("d_mixed", "d_paint", "Δ Sharrows vs Δ Paint    "),
  c("d_paint", "d_sep",   "Δ Paint     vs Δ Protected")
)

cor_summary <- purrr::map_dfr(pairs, function(p) {
  x <- df_changes[[p[1]]]; y <- df_changes[[p[2]]]
  pt <- cor.test(x, y, method = "pearson",  use = "complete.obs")
  st <- cor.test(x, y, method = "spearman", exact = FALSE)
  tibble(
    pair        = p[3],
    pearson_r   = round(pt$estimate, 3),
    pearson_p   = round(pt$p.value,  4),
    spearman_rho= round(st$estimate, 3),
    spearman_p  = round(st$p.value,  4),
    n           = sum(complete.cases(x, y))
  )
})
print(cor_summary)

# Per-period breakdown
cat("\nBy period:\n")
df_changes |>
  group_by(period) |>
  summarise(
    `r(shar,prot)`  = round(cor(d_mixed, d_sep,   use = "complete.obs"), 3),
    `r(shar,paint)` = round(cor(d_mixed, d_paint, use = "complete.obs"), 3),
    `r(paint,prot)` = round(cor(d_paint, d_sep,   use = "complete.obs"), 3),
    `ρ(shar,prot)`  = round(cor(d_mixed, d_sep,   method = "spearman"), 3),
    `ρ(shar,paint)` = round(cor(d_mixed, d_paint, method = "spearman"), 3),
    `ρ(paint,prot)` = round(cor(d_paint, d_sep,   method = "spearman"), 3),
    n = n(),
    .groups = "drop"
  ) |>
  print()

# --- 5b. Share-change correlations (compositional) -----------------------
# Compute each type's share of total CI per city-year, then look at how
# shares changed. A negative correlation between Δshare_mixed and
# Δshare_sep = sharrows gaining ground AT THE EXPENSE OF protected.
cat("\n================================================================\n")
cat("5b. Share-change (compositional) correlations\n")
cat("================================================================\n")
cat("   Negative r(Δshare_mixed, Δshare_sep) would indicate substitution.\n\n")

# Compute shares per city-year
df_shares <- df_raw |>
  mutate(
    total_typed  = sep_km + paint_km + mixed_km + foot_km,
    sh_sep   = sep_km   / pmax(total_typed, 0.001),
    sh_paint = paint_km / pmax(total_typed, 0.001),
    sh_mixed = mixed_km / pmax(total_typed, 0.001),
    sh_foot  = foot_km  / pmax(total_typed, 0.001)
  )

# Period share changes
share_changes <- purrr::map_dfr(seq_len(nrow(period_pairs)), function(i) {
  yf <- period_pairs$yr_from[i]; yt <- period_pairs$yr_to[i]
  pd <- period_pairs$period[i]
  from <- df_shares |> filter(year == yf) |>
    select(city, sh_sep_f = sh_sep, sh_paint_f = sh_paint, sh_mixed_f = sh_mixed)
  to   <- df_shares |> filter(year == yt) |>
    select(city, sh_sep_t = sh_sep, sh_paint_t = sh_paint, sh_mixed_t = sh_mixed)
  inner_join(from, to, by = "city") |>
    mutate(
      period        = pd,
      dsh_sep   = sh_sep_t   - sh_sep_f,
      dsh_paint = sh_paint_t - sh_paint_f,
      dsh_mixed = sh_mixed_t - sh_mixed_f
    )
})

share_cor_summary <- purrr::map_dfr(
  list(c("dsh_mixed","dsh_sep",  "Δshare_Sharrows vs Δshare_Protected"),
       c("dsh_mixed","dsh_paint","Δshare_Sharrows vs Δshare_Paint    "),
       c("dsh_paint","dsh_sep",  "Δshare_Paint    vs Δshare_Protected")),
  function(p) {
    x <- share_changes[[p[1]]]; y <- share_changes[[p[2]]]
    pt <- cor.test(x, y, method = "pearson", use = "complete.obs")
    tibble(
      pair       = p[3],
      pearson_r  = round(pt$estimate, 3),
      p_value    = round(pt$p.value,  4),
      n          = sum(complete.cases(x, y)),
      interpret  = case_when(
        pt$p.value > 0.05            ~ "not significant",
        pt$estimate < -0.2           ~ "substitution (negative)",
        pt$estimate >  0.2           ~ "co-growth (positive)",
        TRUE                         ~ "near zero"
      )
    )
  }
)
print(share_cor_summary)

# --- 5c. Wilcoxon median-split test ------------------------------------
# Split cities into High vs Low sharrow growers (by total period change).
# Test: do high-sharrow-growth cities add significantly less protected CI?
cat("\n================================================================\n")
cat("5c. Wilcoxon test: High vs Low sharrow growth cities\n")
cat("================================================================\n")
cat("   If High-sharrow cities add less protected CI → substitution.\n\n")

wilcox_results <- purrr::map_dfr(unique(df_changes$period), function(pd) {
  sub <- df_changes |> filter(period == pd)
  med_mixed <- median(sub$d_mixed, na.rm = TRUE)
  high <- sub |> filter(d_mixed >= med_mixed)
  low  <- sub |> filter(d_mixed <  med_mixed)

  wt_sep   <- wilcox.test(high$d_sep,   low$d_sep,   exact = FALSE)
  wt_paint <- wilcox.test(high$d_paint, low$d_paint, exact = FALSE)

  tibble(
    period            = pd,
    med_d_sep_high    = round(median(high$d_sep,   na.rm=TRUE), 1),
    med_d_sep_low     = round(median(low$d_sep,    na.rm=TRUE), 1),
    p_sep             = round(wt_sep$p.value,  4),
    med_d_paint_high  = round(median(high$d_paint, na.rm=TRUE), 1),
    med_d_paint_low   = round(median(low$d_paint,  na.rm=TRUE), 1),
    p_paint           = round(wt_paint$p.value, 4),
    sig_sep           = ifelse(wt_sep$p.value   < 0.05, "**", "ns"),
    sig_paint         = ifelse(wt_paint$p.value < 0.05, "**", "ns")
  )
})
cat("med_d_sep_high / med_d_sep_low : median Δprotected km (high vs low sharrow cities)\n")
cat("p_sep / p_paint                : Wilcoxon p-value\n\n")
print(wilcox_results)

# --- 5d. OLS regression: Δprotected ~ Δsharrows + Δtotal ---------------
# Adding Δtotal as control removes the confound that bigger-growing cities
# add more of everything. If Δsharrows is negative and significant here
# → sharrows substitute protected after accounting for overall growth.
cat("\n================================================================\n")
cat("5d. OLS regression: Δprotected ~ Δsharrows + Δtotal (all periods)\n")
cat("================================================================\n")
cat("   Δtotal controls for city size / overall CI investment.\n\n")

lm_sep   <- lm(d_sep   ~ d_mixed + d_total, data = df_changes)
lm_paint <- lm(d_paint ~ d_mixed + d_total, data = df_changes)
lm_mixed <- lm(d_mixed ~ d_sep   + d_total, data = df_changes)  # reciprocal

cat("--- Model: Δ Protected ~ Δ Sharrows + Δ Total ---\n")
print(summary(lm_sep)$coefficients |> round(4))

cat("\n--- Model: Δ Paint ~ Δ Sharrows + Δ Total ---\n")
print(summary(lm_paint)$coefficients |> round(4))

cat("\n--- Model: Δ Sharrows ~ Δ Protected + Δ Total ---\n")
print(summary(lm_mixed)$coefficients |> round(4))

# --- 5e. Protection trajectory classification + plot --------------------
# Classify each city-period into:
#   "Upgrading"   : Δsep > 0 AND Δmixed <= 0  (gaining protection, removing sharrows)
#   "Downgrading" : Δsep <= 0 AND Δmixed > 0  (losing protection, adding sharrows)
#   "Expanding"   : Δsep > 0 AND Δmixed > 0   (both growing — gap-filling)
#   "Contracting" : Δsep <= 0 AND Δmixed <= 0 (both shrinking or flat)
cat("\n================================================================\n")
cat("5e. Protection trajectory classification\n")
cat("================================================================\n")

traj_colors <- c(
  "Upgrading"   = "#054d05",
  "Expanding"   = "#7DBF7A",
  "Downgrading" = "#D95F02",
  "Contracting" = "#CCCCCC"
)

df_traj <- df_changes |>
  mutate(
    trajectory = case_when(
      d_sep >  0 & d_mixed <= 0 ~ "Upgrading",
      d_sep <= 0 & d_mixed >  0 ~ "Downgrading",
      d_sep >  0 & d_mixed >  0 ~ "Expanding",
      TRUE                       ~ "Contracting"
    ),
    trajectory = factor(trajectory, levels = names(traj_colors))
  )

# Summary table
cat("\nTrajectory counts per period:\n")
df_traj |>
  count(period, trajectory) |>
  pivot_wider(names_from = trajectory, values_from = n, values_fill = 0L) |>
  print()

# Stacked bar of trajectories per period
traj_counts <- df_traj |>
  count(period, trajectory) |>
  mutate(period = factor(period, levels = unique(period_pairs$period)))

p_traj <- ggplot(traj_counts, aes(x = period, y = n, fill = trajectory)) +
  geom_bar(stat = "identity", position = "stack") +
  geom_text(aes(label = n),
            position = position_stack(vjust = 0.5),
            size = 4, colour = "white", fontface = "bold") +
  scale_fill_manual(values = traj_colors) +
  labs(
    title    = "City-period protection trajectories: Sharrows vs Protected CI",
    subtitle = paste0(
      "Upgrading: Δprotected > 0, Δsharrows ≤ 0 | ",
      "Downgrading: Δprotected ≤ 0, Δsharrows > 0\n",
      "Expanding: both grow (gap-filling) | Contracting: both shrink or flat"
    ),
    x    = "Period",
    y    = "Number of cities",
    fill = "Trajectory"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title    = element_text(face = "bold"),
    plot.subtitle = element_text(size = 9.5, colour = "grey30"),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

ggsave(file.path(out_dir, "ci_protection_trajectory.png"), p_traj,
       width = 9, height = 6, bg = "white")
cat("[ci_types_stats] Saved ci_protection_trajectory.png\n")

# Also a scatter coloured by trajectory (sharrows vs protected, single panel)
p_traj_scatter <- ggplot(df_traj,
                          aes(x = d_mixed, y = d_sep,
                              colour = trajectory, label = city)) +
  geom_hline(yintercept = 0, colour = "grey60", linetype = "dashed") +
  geom_vline(xintercept = 0, colour = "grey60", linetype = "dashed") +
  geom_point(alpha = 0.7, size = 2.5) +
  geom_text_repel(size = 2.4, max.overlaps = 10, segment.alpha = 0.35) +
  facet_wrap(~period, ncol = 2) +
  scale_colour_manual(values = traj_colors) +
  labs(
    title    = "Δ Sharrows vs Δ Protected CI — trajectory classification",
    subtitle = "Each point = one city. Quadrant = trajectory type.",
    x        = "Δ Sharrows / Mixed traffic (km)",
    y        = "Δ Protected / Separated CI (km)",
    colour   = "Trajectory"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title     = element_text(face = "bold"),
    strip.text     = element_text(face = "bold"),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

ggsave(file.path(out_dir, "ci_trajectory_scatter.png"), p_traj_scatter,
       width = 12, height = 9, bg = "white")
cat("[ci_types_stats] Saved ci_trajectory_scatter.png\n")

# --- Sharrow share per period ---
cat("\n=== Median share of new CI attributed to sharrows per period ===\n")
df_changes |>
  filter(d_total > 0) |>
  group_by(period) |>
  summarise(
    med_sharrow_share = round(median(share_new_mixed, na.rm = TRUE) * 100, 1),
    n = n(),
    .groups = "drop"
  ) |>
  print()

cat("\n[ci_types_stats] All outputs saved to:", out_dir, "\n")
