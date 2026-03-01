# 10_custom_extreme.R
# Generate routing stats and an overline map for a custom "extreme" profile.

library(sf)
library(dplyr)
library(ggplot2)
library(stplanr)
library(httr)
library(parallel)
library(glue)
sf_use_s2(FALSE)

source("code/pipeline_v2/config_v2.R")

custom_scenario <- list(
    cycleway = 1.0,
    path = 1.4,
    service = 1.6,
    residential = 1.5,
    tertiary = 3.5,
    secondary = 5.0,
    primary = 10.0,
    ci_track = 1.0,
    ci_lane = 1.1,
    ci_weak = 1.3,
    ci_foot = 1.4
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

        # calculate straightline distance
        o_pt <- st_point(c(od_pairs$o_lon[i], od_pairs$o_lat[i]))
        d_pt <- st_point(c(od_pairs$d_lon[i], od_pairs$d_lat[i]))
        sl_m <- as.numeric(st_distance(st_sfc(o_pt, crs = 4326), st_sfc(d_pt, crs = 4326)))

        props$sl_m <- sl_m
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

    cat("Loading OD pairs...\n")
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

    od_pairs <- od_pairs |> slice_sample(n = min(5000, nrow(od_pairs)))
    cat(paste0("Sampled ", nrow(od_pairs), " pairs for custom extreme profile.\n"))

    brf_content <- make_brf(custom_scenario)
    brf_path <- "code/pipeline_v2/cycling_ci_sens.brf"
    writeLines(brf_content, brf_path)
    system(paste0("docker cp ", brf_path, " sydney-brouter-2026-1:/brouter/profiles2/cycling_ci_sens.brf"), ignore.stdout = TRUE, ignore.stderr = TRUE)
    Sys.sleep(1)

    cat("Routing 5k pairs for custom extreme profile...\n")
    n_cores <- max(1, detectCores() - 1)
    t0 <- Sys.time()
    routes_sf <- route_scenario_geom(od_pairs, port, "cycling_ci_sens", n_cores)
    t1 <- Sys.time()

    if (!is.null(routes_sf) && nrow(routes_sf) > 0) {
        # Compute summary stats
        routes_df <- st_drop_geometry(routes_sf)
        routes_df$dist_m <- as.numeric(routes_df$track.length)
        routes_df$circuity <- routes_df$dist_m / routes_df$sl_m

        avg_dist <- round(mean(routes_df$dist_m, na.rm = TRUE))
        avg_sl <- round(mean(routes_df$sl_m, na.rm = TRUE))
        avg_circ <- round(mean(routes_df$circuity[is.finite(routes_df$circuity)], na.rm = TRUE), 3)
        n_routed <- nrow(routes_df)
        elapsed <- round(as.numeric(difftime(t1, t0, units = "secs")))

        cat("\n")
        cat("=======================================\n")
        cat("Custom Extreme Profile Results (2026)\n")
        cat("=======================================\n")
        cat(paste0("Pairs Routed:     ", n_routed, "\n"))
        cat(paste0("Avg Distance:     ", avg_dist, "m\n"))
        cat(paste0("Avg Circuity:     ", avg_circ, "\n"))
        cat(paste0("Time Elapsed:     ", elapsed, "s\n"))
        cat("=======================================\n\n")

        routes_sf <- routes_sf[st_geometry_type(routes_sf) %in% c("LINESTRING", "MULTILINESTRING"), ]
        routes_sf <- suppressWarnings(st_cast(st_make_valid(routes_sf), "LINESTRING"))

        routes_sf <- routes_sf |> mutate(attrib = 1)

        cat("Generating Overline map...\n")
        ol <- tryCatch(overline(routes_sf, attrib = "attrib"), error = function(e) {
            cat(paste("  overline error:", e$message, "\n"))
            NULL
        })
        if (!is.null(ol) && nrow(ol) > 0) {
            ol <- ol |>
                mutate(n_trips = .data[["attrib"]]) |>
                filter(n_trips >= 3)
            ol <- st_simplify(ol, dTolerance = 0.001, preserveTopology = TRUE)

            max_trips <- quantile(ol$n_trips, 0.99, na.rm = TRUE)
            min_trips <- 1

            p <- ggplot() +
                geom_sf(
                    data = ol,
                    aes(colour = pmin(n_trips, max_trips), linewidth = pmin(n_trips, max_trips)),
                    alpha = 0.7
                ) +
                scale_colour_viridis_c(option = "magma", name = "Route volume\n(trips / segment)", limits = c(min_trips, max_trips), trans = "sqrt") +
                scale_linewidth_continuous(range = c(0.1, 2.5), limits = c(min_trips, max_trips), guide = "none", trans = "sqrt") +
                theme_minimal(base_size = 12) +
                theme(
                    plot.background = element_rect(fill = "#1a1a2e", colour = NA),
                    panel.background = element_rect(fill = "#1a1a2e", colour = NA),
                    plot.title = element_text(colour = "white", face = "bold", size = 15, hjust = 0.5),
                    plot.subtitle = element_text(colour = "#aaaacc", size = 10, hjust = 0.5),
                    axis.text = element_text(colour = "#888888", size = 7),
                    legend.text = element_text(colour = "white"),
                    legend.title = element_text(colour = "white")
                ) +
                labs(
                    title = paste(city, "— Custom Extreme Cost Structure"),
                    subtitle = paste0("Scenario: 2026 Network | Routed pairs: ", n_routed),
                    x = NULL, y = NULL
                )

            out_png <- file.path(results_dir, "overline_custom_extreme_2026.png")
            ggsave(out_png, p, width = 12, height = 8, dpi = 200, bg = "#1a1a2e")
            cat(paste("Saved customized map:", out_png, "\n"))
        } else {
            cat("Could not generate overline data.\n")
        }
    } else {
        cat("Routing returned empty results.\n")
    }

    file.remove("code/pipeline_v2/cycling_ci_sens.brf")
    system("docker exec sydney-brouter-2026-1 rm -f /brouter/profiles2/cycling_ci_sens.brf", ignore.stdout = TRUE)
}
