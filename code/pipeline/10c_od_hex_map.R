# 10c_od_hex_map.R
# Generate a facet map comparing Origin vs Destination densities in the H3 grid

library(sf)
library(ggplot2)
library(dplyr)
library(viridis)
library(h3jsr)
library(patchwork)

# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run

cat("Starting OD Density Facet Mapping...\n")

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)
    results_dir <- file.path(city_dir, "results")
    dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

    # Check if files exist
    origins_path <- file.path(city_dir, "origins.gpkg")
    destinations_path <- file.path(city_dir, "destinations.gpkg")
    poly_path <- file.path(city_dir, paste0(city_lower, "_10km.gpkg"))

    if (!all(file.exists(origins_path, destinations_path, poly_path))) {
        warning(paste("Missing OD data files for", city))
        next
    }

    cat(paste("  Processing", city, "...\n"))

    # Load data
    origins <- st_read(origins_path, quiet = TRUE)
    destinations <- st_read(destinations_path, quiet = TRUE)
    city_poly <- st_read(poly_path, quiet = TRUE)

    cat("    Aggregating by H3 cell...\n")

    # For Origins
    orig_counts_raw <- origins %>%
        st_drop_geometry() %>%
        group_by(h3_address) %>%
        summarise(n = n(), .groups = "drop")

    orig_hex <- cell_to_polygon(orig_counts_raw$h3_address, simple = FALSE)
    orig_counts <- orig_hex %>%
        left_join(orig_counts_raw, by = "h3_address")

    # For Destinations
    dest_counts_raw <- destinations %>%
        st_drop_geometry() %>%
        group_by(h3_address) %>%
        summarise(n = n(), .groups = "drop")

    dest_hex <- cell_to_polygon(dest_counts_raw$h3_address, simple = FALSE)
    dest_counts <- dest_hex %>%
        left_join(dest_counts_raw, by = "h3_address")

    # Common theme settings
    map_theme <- theme_void() +
        theme(
            plot.background = element_rect(fill = "white", color = NA),
            legend.position = "bottom",
            legend.text = element_text(color = "black", size = 7),
            legend.title = element_text(color = "black", size = 9, face = "bold"),
            plot.title = element_text(color = "black", face = "bold", hjust = 0.5, size = 14, margin = margin(t = 10, b = 5)),
            plot.subtitle = element_text(color = "#555555", hjust = 0.5, size = 9),
            plot.margin = margin(5, 5, 5, 5)
        )

    # Plot Origins (Left - Magma)
    p_orig <- ggplot() +
        geom_sf(data = city_poly, fill = "#f0f0f0", color = "#888888", alpha = 0.5, size = 0.1) +
        geom_sf(data = orig_counts, aes(fill = n), color = NA) +
        scale_fill_viridis_c(option = "magma", name = "Trip Origins", trans = "sqrt") +
        labs(title = "Sampled Origins", subtitle = "Lognormal decay from destinations") +
        map_theme

    # Plot Destinations (Right - Viridis)
    p_dest <- ggplot() +
        geom_sf(data = city_poly, fill = "#f0f0f0", color = "#888888", alpha = 0.5, size = 0.1) +
        geom_sf(data = dest_counts, aes(fill = n), color = NA) +
        scale_fill_viridis_c(option = "viridis", name = "Trip Destinations", trans = "sqrt") +
        labs(title = "Sampled Destinations", subtitle = "Weighted by building volume") +
        map_theme

    # Combine with patchwork: Origins Left, Destinations Right
    combined_title <- paste("OD Density:", city)
    final_plot <- (p_orig | p_dest) +
        plot_annotation(
            title = combined_title,
            subtitle = paste("Comparison of 20k OD pairs distributed across H3 Res", h3_res, "grid"),
            theme = theme(
                plot.background = element_rect(fill = "white", color = NA),
                plot.title = element_text(color = "black", size = 20, face = "bold", hjust = 0.5, margin = margin(t = 15)),
                plot.subtitle = element_text(color = "#555555", size = 12, hjust = 0.5, margin = margin(b = 10))
            )
        )

    out_file <- file.path(results_dir, "od_density_facet_map.png")
    ggsave(out_file, final_plot, width = 16, height = 9, dpi = 300)

    # Also save a copy in the general images folder
    general_out <- file.path("images", paste0(city_lower, "_od_validation_facet.png"))
    ggsave(general_out, final_plot, width = 16, height = 9, dpi = 300)

    cat(paste("  Successfully saved OD density map to:", out_file, "\n"))
}

cat("OD Density Mapping completed.\n")
