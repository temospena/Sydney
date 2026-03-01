# 06_overline_maps.R
# Create overline route maps for the 3 years (2016, 2021, 2026)
# Uses stplanr::overline() to aggregate route volumes and produce a 3-panel map.

library(sf)
library(dplyr)
library(ggplot2)
library(stplanr)
sf_use_s2(FALSE)

source("code/pipeline_v2/config_v2.R")

YEARS <- names(BROUTER_PORTS) # c("16", "21", "26")
V_YEARS <- c("2016", "2021", "2026")

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)
    results_dir <- file.path(city_dir, "results")
    dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

    cat(paste("Building overline maps for", city, "...\n"))

    # ---- Load the city polygon (for bounding box clip) ----
    city_poly_path <- file.path(city_dir, paste0(city_lower, "_10km.gpkg"))
    city_poly <- if (file.exists(city_poly_path)) st_read(city_poly_path, quiet = TRUE) else NULL

    # ---- Collect routes for all years ----
    all_ols <- list()

    for (i in seq_along(YEARS)) {
        yr <- YEARS[i]
        v_yr <- V_YEARS[i]
        routes_path <- file.path(city_dir, paste0("routes_v2_", yr, ".gpkg"))

        if (!file.exists(routes_path)) {
            cat(paste("  Routes file missing for", city, yr, "- skipping\n"))
            next
        }

        routes <- st_read(routes_path, quiet = TRUE) |> st_transform(4326)

        if (nrow(routes) == 0) next

        # Keep only LINESTRING geometries (drop MULTILINESTRING if any)
        routes <- routes[st_geometry_type(routes) %in% c("LINESTRING", "MULTILINESTRING"), ]

        cat(paste("  Overline for year", v_yr, "\n"))

        ol <- tryCatch(
            overline(routes, attrib = "trip_id"),
            error = function(e) {
                cat(paste("  overline error:", e$message, "\n"))
                NULL
            }
        )

        if (is.null(ol) || nrow(ol) == 0) next

        # Normalize volume to trips per segment per km for comparability
        ol <- ol |> mutate(year = v_yr, n_trips = .data[["trip_id"]])
        all_ols[[v_yr]] <- ol
    }

    if (length(all_ols) == 0) {
        cat(paste("  No overline data for", city, "- skipping\n"))
        next
    }

    routes_combined <- bind_rows(all_ols)

    # ---- Build the 3-panel ggplot map ----
    # Define a common colour scale range
    max_trips <- quantile(routes_combined$n_trips, 0.99, na.rm = TRUE) # cap at 99th pct
    min_trips <- 1

    p <- ggplot() +
        geom_sf(
            data = routes_combined,
            aes(colour = pmin(n_trips, max_trips), linewidth = pmin(n_trips, max_trips)),
            alpha = 0.7
        ) +
        facet_wrap(~year, ncol = 3) +
        scale_colour_viridis_c(
            option = "magma",
            name   = "Route volume\n(trips / segment)",
            limits = c(min_trips, max_trips),
            trans  = "sqrt"
        ) +
        scale_linewidth_continuous(
            range  = c(0.1, 2.5),
            limits = c(min_trips, max_trips),
            guide  = "none",
            trans  = "sqrt"
        ) +
        theme_minimal(base_size = 12) +
        theme(
            plot.background  = element_rect(fill = "#1a1a2e", colour = NA),
            panel.background = element_rect(fill = "#1a1a2e", colour = NA),
            strip.background = element_rect(fill = "#16213e", colour = NA),
            strip.text       = element_text(colour = "white", face = "bold", size = 13),
            plot.title       = element_text(colour = "white", face = "bold", size = 15, hjust = 0.5),
            plot.subtitle    = element_text(colour = "#aaaacc", size = 10, hjust = 0.5),
            axis.text        = element_text(colour = "#888888", size = 7),
            legend.text      = element_text(colour = "white"),
            legend.title     = element_text(colour = "white"),
            legend.position  = "right"
        ) +
        labs(
            title = paste(city, "— BRouter Cycling Routes (V2)"),
            subtitle = paste0("Overline aggregation · n_od_pairs = ", n_od_pairs),
            x = NULL, y = NULL
        )

    out_png <- file.path(results_dir, "overline_routes_v2.png")
    ggsave(out_png, p, width = 16, height = 6.5, dpi = 200, bg = "#1a1a2e")
    cat(paste("  Saved:", out_png, "\n"))
}

cat("Overline maps done.\n")
