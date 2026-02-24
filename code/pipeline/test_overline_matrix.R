# test_overline_matrix.R
# Test script to generate a 3x4 grid of overline maps for Sydney

library(tidyverse)
library(sf)
library(stplanr)
library(tmap)

source("code/pipeline/config.R")
city <- "Sydney"
city_lower <- tolower(city)
city_dir <- file.path(data_dir, city_lower)
results_dir <- file.path(city_dir, "results")

cat("Starting 3x4 Overline Map generation for", city, "\n")

# Process and overline each scenario to save RAM
overlines_list <- list()

for (lts_level in 1:4) {
    for (yr in years) {
        cat("Processing LTS", lts_level, "Year", yr, "\n")
        res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
        res_file_long <- file.path(city_dir, paste0("trips_", city_lower, "_20", yr, "_lts", lts_level, ".rds"))

        trips_to_read <- NULL
        if (file.exists(res_file)) {
            trips_to_read <- res_file
        } else if (file.exists(res_file_long)) {
            trips_to_read <- res_file_long
        }

        if (!is.null(trips_to_read)) {
            trips <- readRDS(trips_to_read) |>
                mutate(year = paste0("20", yr), lts = paste0("LTS ", lts_level), trips = 1)

            if (nrow(trips) > 0) {
                ovline <- overline2(trips, attrib = "trips") |>
                    mutate(year = paste0("20", yr), lts = paste0("LTS ", lts_level))
                overlines_list[[paste0("lts", lts_level, "_", yr)]] <- ovline
            }
            rm(trips)
            gc()
        }
    }
}

cat("Combining overline maps...\n")
map_data <- bind_rows(overlines_list) |> filter(trips > 2) # make it less heavy

# Ensure correct ordering
map_data$year <- factor(map_data$year, levels = c("2016", "2021", "2026"))
map_data$lts <- factor(map_data$lts, levels = c("LTS 1", "LTS 2", "LTS 3", "LTS 4"))

cat("Generating ggplot facet grid...\n")

p_map <- ggplot() +
    geom_sf(data = map_data, aes(linewidth = trips, color = trips)) +
    scale_color_viridis_c(option = "inferno", direction = -1) +
    scale_linewidth_continuous(range = c(0.1, 2.5)) +
    facet_grid(lts ~ year, switch = "y") +
    theme_minimal() +
    theme(
        axis.text = element_blank(),
        axis.ticks = element_blank(),
        panel.grid = element_blank(),
        strip.placement = "outside",
        strip.text.y.left = element_text(angle = 90, size = 12), # bigger letters
        strip.text.x = element_text(size = 12), # bigger letters
        legend.position = "bottom",
        legend.direction = "horizontal",
        legend.key.width = unit(1.5, "cm")
    ) +
    labs(
        title = paste("Routing Density Matrix -", city),
        color = "Trips Volume",
        linewidth = "Trips Volume"
    )

out_file <- file.path(results_dir, "overline_matrix_test.png")
cat("Saving to", out_file, "...\n")
ggsave(out_file, p_map, width = 9, height = 12, bg = "white", dpi = 300)

cat("Done!\n")
