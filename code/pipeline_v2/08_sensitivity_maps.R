# 08_sensitivity_maps.R
# Generate overline maps for the 4 sensitivity scenarios.

library(sf)
library(dplyr)
library(ggplot2)
library(stplanr)
library(httr)
library(parallel)
library(glue)
sf_use_s2(FALSE)

source("code/pipeline_v2/config_v2.R")

scenarios <- list(
    A_current = list(cycleway = 1.0, path = 1.1, service = 1.15, residential = 1.3, tertiary = 1.5, secondary = 1.8, primary = 3.0, ci_track = 1.0, ci_lane = 1.1, ci_weak = 1.2, ci_foot = 1.3),
    B_wider = list(cycleway = 1.0, path = 1.15, service = 1.2, residential = 1.6, tertiary = 2.0, secondary = 2.5, primary = 5.0, ci_track = 1.0, ci_lane = 1.15, ci_weak = 1.3, ci_foot = 1.4),
    C_narrow = list(cycleway = 1.0, path = 1.05, service = 1.08, residential = 1.1, tertiary = 1.2, secondary = 1.4, primary = 2.0, ci_track = 1.0, ci_lane = 1.05, ci_weak = 1.07, ci_foot = 1.1),
    D_extreme = list(cycleway = 1.0, path = 1.3, service = 1.4, residential = 2.5, tertiary = 3.5, secondary = 5.0, primary = 10.0, ci_track = 1.0, ci_lane = 1.2, ci_weak = 1.5, ci_foot = 1.8)
)

make_brf <- function(p) {
    glue::glue("
---context:global

assign validForBikes = true
assign validForCars  = false
assign validForFoot  = false
assign isbike = true

---context:node
assign initialcost = 0
assign turncost    = 0

---context:way
assign switchpoint = false

assign is_ferry = route=ferry

assign hm =
  if ( highway=cycleway                                       ) then {p$cycleway}
  else if ( highway=path|track                               ) then {p$path}
  else if ( highway=service                                  ) then {p$service}
  else if ( highway=residential|living_street|unclassified   ) then {p$residential}
  else if ( highway=tertiary|tertiary_link                   ) then {p$tertiary}
  else if ( highway=secondary|secondary_link                 ) then {p$secondary}
  else if ( highway=primary|primary_link                     ) then {p$primary}
  else if ( highway=footway                                  ) then 2.5
  else if ( highway=steps                                    ) then 6.0
  else if ( highway=motorway|motorway_link|trunk|trunk_link  ) then 9999.0
  else 2.0

assign has_track =
  or highway=cycleway
     or cycleway=track
        or cycleway=opposite_track
           or cycleway:right=track
              cycleway:left=track

assign has_lane =
  or cycleway=lane
     or cycleway=opposite_lane
        or cycleway:right=lane
           or cycleway:left=lane
              or cycleway:right=opposite_lane
                 cycleway:left=opposite_lane

assign has_weak =
  or cycleway=shared_lane
     cycleway=share_busway

assign has_foot =
  and highway=path|footway|pedestrian
      bicycle=yes|designated

assign hw =
  if ( is_ferry  ) then 999.0
  else if ( has_track ) then {p$ci_track}
  else if ( has_lane  ) then {p$ci_lane}
  else if ( has_weak  ) then {p$ci_weak}
  else if ( has_foot  ) then {p$ci_foot}
  else hm

assign costfactor = hw
")
}

route_scenario_geom <- function(od_pairs, port, profile_name, n_cores) {
    route_one <- function(i) {
        url <- paste0(
            "http://localhost:", port, "/brouter?lonlats=",
            od_pairs$o_lon[i], ",", od_pairs$o_lat[i], "|",
            od_pairs$d_lon[i], ",", od_pairs$d_lat[i],
            "&profile=", profile_name, "&alternativeidx=0&format=geojson"
        )
        res <- tryCatch(GET(url, timeout(20)), error = function(e) NULL)
        if (is.null(res) || status_code(res) != 200) {
            return(NULL)
        }
        txt <- content(res, as = "text", encoding = "UTF-8")
        feat <- tryCatch(st_read(txt, quiet = TRUE), error = function(e) NULL)
        if (is.null(feat) || nrow(feat) == 0) {
            return(NULL)
        }

        props <- feat[1, ]
        dur_s <- as.numeric(props[["total.time"]])
        if (!is.na(dur_s) && dur_s > 7200) {
            return(NULL)
        }

        list_cols <- sapply(props, is.list)
        list_cols[names(list_cols) == attr(props, "sf_column")] <- FALSE
        for (col in names(list_cols)[list_cols]) props[[col]] <- NULL

        props$trip_id <- od_pairs$trip_id[i]
        return(props)
    }

    res_list <- mclapply(seq_len(nrow(od_pairs)), route_one, mc.cores = n_cores)
    res_valid <- Filter(Negate(is.null), res_list)
    if (length(res_valid) == 0) {
        return(NULL)
    }

    unique_routes <- dplyr::bind_rows(res_valid)
    unique_routes_sf <- st_as_sf(unique_routes)
    if (st_crs(unique_routes_sf)$epsg != 4326) st_crs(unique_routes_sf) <- 4326
    return(unique_routes_sf)
}

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)
    results_dir <- file.path(city_dir, "results")

    port <- BROUTER_PORTS["26"] # 2026 port

    orig <- st_read(file.path(city_dir, "origins_v2.gpkg"), quiet = TRUE)
    dest <- st_read(file.path(city_dir, "destinations_v2.gpkg"), quiet = TRUE)

    set.seed(42)
    od_pairs <- data.frame(
        trip_id = orig$trip_id,
        o_lon = st_coordinates(orig)[, 1],
        o_lat = st_coordinates(orig)[, 2],
        d_lon = st_coordinates(dest)[, 1],
        d_lat = st_coordinates(dest)[, 2]
    ) |>
        distinct(o_lon, o_lat, d_lon, d_lat, .keep_all = TRUE)

    od_pairs <- od_pairs |> slice_sample(n = min(1000, nrow(od_pairs)))

    all_ols <- list()
    for (nm in names(scenarios)) {
        p <- scenarios[[nm]]
        brf_content <- make_brf(p)
        brf_path <- "code/pipeline_v2/cycling_ci_sens.brf"
        writeLines(brf_content, brf_path)
        system(paste0("docker cp ", brf_path, " sydney-brouter-2026-1:/brouter/profiles2/cycling_ci_sens.brf"), ignore.stdout = TRUE, ignore.stderr = TRUE)
        Sys.sleep(1)

        cat(paste0("Routing map scenario ", nm, "...\n"))
        n_cores <- max(1, detectCores() - 1)
        routes_sf <- route_scenario_geom(od_pairs, port, "cycling_ci_sens", n_cores)

        if (!is.null(routes_sf) && nrow(routes_sf) > 0) {
            routes_sf <- routes_sf[st_geometry_type(routes_sf) %in% c("LINESTRING", "MULTILINESTRING"), ]
            routes_sf <- suppressWarnings(st_cast(st_make_valid(routes_sf), "LINESTRING"))

            ol <- tryCatch(overline(routes_sf, attrib = "trip_id"), error = function(e) NULL)
            if (!is.null(ol) && nrow(ol) > 0) {
                ol <- ol |>
                    mutate(scenario = nm, n_trips = .data[["trip_id"]]) |>
                    filter(n_trips >= 3)
                ol <- st_simplify(ol, dTolerance = 0.001, preserveTopology = TRUE)
                all_ols[[nm]] <- ol
            }
        }
    }

    file.remove("code/pipeline_v2/cycling_ci_sens.brf")
    system("docker exec sydney-brouter-2026-1 rm -f /brouter/profiles2/cycling_ci_sens.brf", ignore.stdout = TRUE)

    if (length(all_ols) > 0) {
        routes_combined <- bind_rows(all_ols)

        max_trips <- quantile(routes_combined$n_trips, 0.99, na.rm = TRUE)
        min_trips <- 1

        p <- ggplot() +
            geom_sf(
                data = routes_combined,
                aes(colour = pmin(n_trips, max_trips), linewidth = pmin(n_trips, max_trips)),
                alpha = 0.7
            ) +
            facet_wrap(~scenario, ncol = 2) +
            scale_colour_viridis_c(option = "magma", name = "Route volume\n(trips / segment)", limits = c(min_trips, max_trips), trans = "sqrt") +
            scale_linewidth_continuous(range = c(0.1, 2.5), limits = c(min_trips, max_trips), guide = "none", trans = "sqrt") +
            theme_minimal(base_size = 12) +
            theme(
                plot.background = element_rect(fill = "#1a1a2e", colour = NA),
                panel.background = element_rect(fill = "#1a1a2e", colour = NA),
                strip.background = element_rect(fill = "#16213e", colour = NA),
                strip.text = element_text(colour = "white", face = "bold", size = 13),
                plot.title = element_text(colour = "white", face = "bold", size = 15, hjust = 0.5),
                axis.text = element_text(colour = "#888888", size = 7),
                legend.text = element_text(colour = "white"),
                legend.title = element_text(colour = "white")
            ) +
            labs(title = paste(city, "— Sensitivity Analysis Scenarios"), x = NULL, y = NULL)

        out_png <- file.path(results_dir, "overline_sensitivity_v2.png")
        ggsave(out_png, p, width = 12, height = 10, dpi = 200, bg = "#1a1a2e")
        cat(paste("  Saved:", out_png, "\n"))
    }
}
