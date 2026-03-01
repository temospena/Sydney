# 07_sensitivity_analysis.R
# Sensitivity analysis on cycling_ci.brf cost factor weights.
# Runs BRouter routing for Lisbon with several weight configurations
# using the existing 1k OD pairs (fast) and compares circuity and CI %.
#
# Usage: Rscript -e "source('code/pipeline_v2/07_sensitivity_analysis.R')"
# (Requires Docker containers to be running: docker compose up -d)

library(sf)
library(dplyr)
library(httr)
library(parallel)
sf_use_s2(FALSE)

source("code/pipeline_v2/config_v2.R")

# ------------------------------------------------------------------
# Define sensitivity scenarios
# Each scenario is a named list that gets written as a .brf file,
# routed against the 2026 port (most CI), and summarised.
# ------------------------------------------------------------------
scenarios <- list(
    # Scenario A: Current production weights (as in cycling_ci.brf)
    # cycleway=1.0, residential=1.3, primary=3.0
    A_current = list(
        cycleway = 1.0, path = 1.1, service = 1.15,
        residential = 1.3, tertiary = 1.5, secondary = 1.8, primary = 3.0,
        ci_track = 1.0, ci_lane = 1.1, ci_weak = 1.2, ci_foot = 1.3
    ),

    # Scenario B: Wider gap — more CI preference
    # cycleway=1.0, residential=1.6, primary=5.0
    B_wider = list(
        cycleway = 1.0, path = 1.15, service = 1.2,
        residential = 1.6, tertiary = 2.0, secondary = 2.5, primary = 5.0,
        ci_track = 1.0, ci_lane = 1.15, ci_weak = 1.3, ci_foot = 1.4
    ),

    # Scenario C: Narrow gap — minimal CI preference (nearly shortest-path)
    # cycleway=1.0, residential=1.1, primary=2.0
    C_narrow = list(
        cycleway = 1.0, path = 1.05, service = 1.08,
        residential = 1.1, tertiary = 1.2, secondary = 1.4, primary = 2.0,
        ci_track = 1.0, ci_lane = 1.05, ci_weak = 1.07, ci_foot = 1.1
    ),

    # Scenario D: Very wide gap — extreme CI preference
    # cycleway=1.0, residential=2.5, primary=10.0
    D_extreme = list(
        cycleway = 1.0, path = 1.3, service = 1.4,
        residential = 2.5, tertiary = 3.5, secondary = 5.0, primary = 10.0,
        ci_track = 1.0, ci_lane = 1.2, ci_weak = 1.5, ci_foot = 1.8
    )
)

# ------------------------------------------------------------------
# BRF template function
# ------------------------------------------------------------------
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

# ------------------------------------------------------------------
# Helper: route a batch of OD pairs against one BRouter port
# Returns data.frame with avg_dist, avg_circuity, pct_ci
# ------------------------------------------------------------------
route_scenario <- function(od_pairs, port, profile_name, n_cores) {
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
        props <- feat[1, ] |> st_drop_geometry()
        dist_m <- as.numeric(props[["track.length"]])
        dur_s <- as.numeric(props[["total.time"]])
        if (is.na(dist_m) || dur_s > 7200) {
            return(NULL)
        }
        # Straight-line distance for circuity
        o_pt <- st_point(c(od_pairs$o_lon[i], od_pairs$o_lat[i]))
        d_pt <- st_point(c(od_pairs$d_lon[i], od_pairs$d_lat[i]))
        sl_m <- as.numeric(st_distance(
            st_sfc(o_pt, crs = 4326), st_sfc(d_pt, crs = 4326)
        ))
        list(dist_m = dist_m, sl_m = sl_m, circuity = dist_m / sl_m)
    }

    res_list <- mclapply(seq_len(nrow(od_pairs)), route_one, mc.cores = n_cores)
    res_valid <- Filter(Negate(is.null), res_list)

    if (length(res_valid) == 0) {
        return(NULL)
    }
    df <- bind_rows(lapply(res_valid, as.data.frame))
    data.frame(
        n_routed = nrow(df),
        avg_dist_m = round(mean(df$dist_m, na.rm = TRUE)),
        avg_sl_m = round(mean(df$sl_m, na.rm = TRUE)),
        avg_circuity = round(mean(df$circuity[is.finite(df$circuity)], na.rm = TRUE), 3)
    )
}

# ------------------------------------------------------------------
# Main: load 1k OD pairs, run each scenario against port 17773 (2026)
# ------------------------------------------------------------------
if (!requireNamespace("glue", quietly = TRUE)) install.packages("glue")
library(glue)

city <- "lisbon"
city_dir <- file.path(data_dir, city)
port <- BROUTER_PORTS["26"] # use 2026 for max CI variation
n_cores <- max(1, detectCores() - 1)

# Use a fixed small sample of 500 unique pairs for speed
orig <- st_read(file.path(city_dir, "origins_v2.gpkg"), quiet = TRUE)
dest <- st_read(file.path(city_dir, "destinations_v2.gpkg"), quiet = TRUE)

od_pairs <- data.frame(
    o_lon = st_coordinates(orig)[, 1],
    o_lat = st_coordinates(orig)[, 2],
    d_lon = st_coordinates(dest)[, 1],
    d_lat = st_coordinates(dest)[, 2]
) |>
    distinct(o_lon, o_lat, d_lon, d_lat) |>
    slice_sample(n = min(500, nrow(distinct(data.frame(
        o_lon = st_coordinates(orig)[, 1], o_lat = st_coordinates(orig)[, 2],
        d_lon = st_coordinates(dest)[, 1], d_lat = st_coordinates(dest)[, 2]
    )))))

cat(paste0("Running sensitivity analysis on ", nrow(od_pairs), " unique OD pairs (port ", port, ")...\n\n"))

results <- list()

for (nm in names(scenarios)) {
    p <- scenarios[[nm]]

    # Write .brf to Docker profiles2 (cycling_ci_sens.brf)
    brf_content <- make_brf(p)
    brf_path <- "code/pipeline_v2/cycling_ci_sens.brf"
    writeLines(brf_content, brf_path)

    # Also copy into the running container's profiles2
    system(paste0("docker cp ", brf_path, " sydney-brouter-2026-1:/brouter/profiles2/cycling_ci_sens.brf"),
        ignore.stdout = TRUE, ignore.stderr = TRUE
    )

    Sys.sleep(1) # let BRouter reload profile cache

    cat(paste0("Scenario ", nm, ": residential=", p$residential, " primary=", p$primary, " ci_track=", p$ci_track, "\n"))
    t0 <- Sys.time()
    r <- route_scenario(od_pairs, port, "cycling_ci_sens", n_cores)
    t1 <- Sys.time()

    if (!is.null(r)) {
        r$scenario <- nm
        r$residential <- p$residential
        r$primary <- p$primary
        r$ci_track <- p$ci_track
        r$ci_lane <- p$ci_lane
        r$elapsed_s <- round(as.numeric(difftime(t1, t0, units = "secs")))
        results[[nm]] <- r
        cat(paste0(
            "  → avg_dist=", r$avg_dist_m, "m  avg_circuity=", r$avg_circuity,
            "  n=", r$n_routed, "  (", r$elapsed_s, "s)\n"
        ))
    }
}

# Clean up temp profile
file.remove("code/pipeline_v2/cycling_ci_sens.brf")
system("docker exec sydney-brouter-2026-1 rm -f /brouter/profiles2/cycling_ci_sens.brf",
    ignore.stdout = TRUE
)

# Summary table
summary_df <- bind_rows(results) |>
    select(scenario, residential, primary, ci_track, ci_lane, avg_dist_m, avg_circuity, n_routed)

cat("\n=== Sensitivity Analysis Results ===\n")
print(summary_df, row.names = FALSE)

out_csv <- file.path(data_dir, "sensitivity_weights_lisbon.csv")
write.csv(summary_df, out_csv, row.names = FALSE)
cat(paste0("\nSaved to: ", out_csv, "\n"))
