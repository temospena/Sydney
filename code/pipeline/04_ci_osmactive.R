# 04_ci_osmactive.R
# Extract historical cycling network infrastructure using osmactive and custom OSM tags logic

library(osmactive)
library(osmextract)
library(sf)
library(dplyr)
sf_use_s2(TRUE)
options(timeout = 3600)

# Load global configuration
source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run
VERSIONS <- versions

# Use the global region_map from config.R
# This avoids inconsistent naming (e.g. Barcelona as 'spain' vs 'cataluna')
# that leads to duplicate downloads of the same data.

# Custom ci classification logic ported from 02_ci_osmextract_custom.R
cycleway_cols <- function(x) {
    names(x)[grepl("^cycleway($|[:_])", names(x), ignore.case = TRUE)]
}
has_cycleway_vals <- function(x, vals) {
    cols <- cycleway_cols(x)
    if (!length(cols)) {
        return(rep(FALSE, nrow(x)))
    }
    vals <- tolower(vals)
    out <- rep(FALSE, nrow(x))
    for (cc in cols) {
        v <- tolower(trimws(as.character(x[[cc]])))
        v[is.na(v)] <- ""
        hit <- vapply(strsplit(v, ";", fixed = TRUE), function(parts) any(trimws(parts) %in% vals), logical(1))
        out <- out | hit
    }
    out
}

STRONG_ONROAD_VALS <- c("track", "opposite_track")
MODERATE_ONROAD_VALS <- c("lane", "opposite_lane")
WEAK_ONROAD_VALS <- c("share_busway", "shared_lane")
FOOT_SHARED_HWY <- c("path", "footway", "pedestrian")
FOOT_SHARED_BIC <- c("yes", "designated")
FOOT_SHARED_FOOT <- c("yes", "designated")
PAVEMENT_LANE_HWY <- c("footway", "path", "pedestrian")
PAVEMENT_LANE_BIC <- c("designated")

classify_custom_ci <- function(lines_m) {
    highway <- tolower(trimws(as.character(lines_m$highway)))
    if ("bicycle" %in% names(lines_m)) bicycle <- tolower(trimws(as.character(lines_m$bicycle))) else bicycle <- rep(NA_character_, nrow(lines_m))
    if ("foot" %in% names(lines_m)) foot <- tolower(trimws(as.character(lines_m$foot))) else foot <- rep(NA_character_, nrow(lines_m))
    if ("segregated" %in% names(lines_m)) segregated <- tolower(trimws(as.character(lines_m$segregated))) else segregated <- rep(NA_character_, nrow(lines_m))
    if ("bicycle_road" %in% names(lines_m)) bicycle_road <- tolower(trimws(as.character(lines_m$bicycle_road))) else bicycle_road <- rep(NA_character_, nrow(lines_m))


    is_cyclewy <- !is.na(highway) & highway == "cycleway"

    has_strong_onroad <- has_cycleway_vals(lines_m, STRONG_ONROAD_VALS)
    has_moderate_onroad <- has_cycleway_vals(lines_m, MODERATE_ONROAD_VALS)
    has_weak_onroad <- has_cycleway_vals(lines_m, WEAK_ONROAD_VALS)

    is_bicycle_road <- (!is.na(highway) & highway == "residential") &
        (!is.na(bicycle_road) & bicycle_road == "yes")

    is_foot_shared <- (!is.na(highway) & highway %in% FOOT_SHARED_HWY) &
        (!is.na(bicycle) & bicycle %in% FOOT_SHARED_BIC) &
        (!is.na(foot) & foot %in% FOOT_SHARED_FOOT) &
        !(segregated %in% "yes")

    is_pavement_lane <- (!is.na(highway) & highway %in% PAVEMENT_LANE_HWY) &
        (!is.na(bicycle) & bicycle %in% PAVEMENT_LANE_BIC) &
        (TRUE | !(segregated %in% "yes"))

    lines_m$cycle_cat <- NA_character_
    lines_m$cycle_cat[is_cyclewy] <- "strong_ci"

    sel_foot <- (is_foot_shared | is_pavement_lane) & is.na(lines_m$cycle_cat)
    lines_m$cycle_cat[sel_foot] <- "shared_foot"

    sel_other <- is.na(lines_m$cycle_cat)
    lines_m$cycle_cat[sel_other & has_strong_onroad] <- "strong_ci"

    sel_other <- is.na(lines_m$cycle_cat)
    lines_m$cycle_cat[sel_other & has_moderate_onroad] <- "moderate_ci"

    sel_other <- is.na(lines_m$cycle_cat)
    lines_m$cycle_cat[sel_other & (has_weak_onroad | is_bicycle_road)] <- "weak_ci"

    lines_m <- lines_m[!is.na(lines_m$cycle_cat), , drop = FALSE]

    lines_m$infra5 <- factor(lines_m$cycle_cat,
        levels = c("strong_ci", "moderate_ci", "weak_ci", "shared_foot"),
        labels = c("Separated cycling infrastructure", "Painted on-road cycle lane", "Mixed traffic (motor vehicles with light infra)", "Cycling on pedestrian infrastructure")
    )
    return(lines_m)
}


for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)

    perim_path <- file.path(city_dir, paste0(city_lower, "_10km.gpkg"))
    if (!file.exists(perim_path)) {
        warning(paste("Missing perimeter for", city, "- Skipping..."))
        next
    }

    perim <- sf::st_read(perim_path, quiet = TRUE) |> sf::st_make_valid()
    if (sf::st_crs(perim)$epsg != 4326) perim <- sf::st_transform(perim, 4326)

    for (v in VERSIONS) {
        v_short <- substr(v, 1, 2)
        infra_region <- get_geofabrik_region(city, v_short)

        out_path <- file.path(city_dir, paste0(city_lower, "_ci_osmactive_", v, ".gpkg"))

        if (file.exists(out_path) && !FORCE_RERUN) {
            cat(paste("CI for", city, "version", v, "already exists. Skipping extraction...\n"))
            next
        }

        cat(paste("Extracting CI for", city, "version", v, "...\n"))

        # Prioritize the locally cropped PBF from step 03, fallback to raw file, then URL.
        # infra_region is the full path, e.g. "north-america/us/illinois".
        # Files on disk use only the stem (last component), e.g. "illinois".
        infra_stem <- gsub(".*/", "", infra_region)
        cropped_pbf <- file.path(city_dir, paste0(city_lower, "_", v_short, ".osm.pbf"))
        raw_pbf <- file.path(osm_raw_dir, paste0("geofabrik_", infra_stem, "-", v, ".osm.pbf"))

        # Determine source: local cropped PBF -> raw PBF -> Geofabrik URL.
        # oe_read() handles all three correctly:
        #   local path -> reads directly
        #   HTTP URL   -> downloads to download_directory, then reads
        # NEVER use get_travel_network() / oe_get() here: those call oe_match()
        # which treats the string as a city name and fails for both paths and URLs.
        if (file.exists(cropped_pbf)) {
            source_path <- cropped_pbf
        } else if (file.exists(raw_pbf)) {
            source_path <- raw_pbf
        } else {
            source_path <- get_geofabrik_url(city, v_short)
        }

        tryCatch(
            {
                osm <- osmextract::oe_read(
                    file_path             = source_path,
                    layer                 = "lines",
                    extra_tags            = c(osmactive::et_active(), "bicycle_road"),
                    boundary              = perim,
                    boundary_type         = "clipsrc",
                    force_vectortranslate = FORCE_RERUN,
                    download_directory    = osm_raw_dir,
                    quiet                 = FALSE
                )
                # Replicate get_travel_network() post-read filters
                osm <- dplyr::filter(osm, !is.na(highway))
                osm <- dplyr::filter(osm, is.na(service))
                osm <- dplyr::select(osm, -dplyr::any_of(c("waterway", "aerialway", "barrier", "manmade")))
                osm$n_bus_lanes <- osmactive:::count_bus_lanes(osm)

                cycle_net <- osmactive::get_cycling_network(osm)

                cycle_net <- classify_custom_ci(cycle_net)

                cycle_net <- cycle_net |>
                    sf::st_transform(4326)

                sf::st_write(cycle_net, out_path, driver = "GPKG", append = FALSE, quiet = TRUE)
                cat(paste("Successfully saved", out_path, "\n"))
            },
            error = function(cond) {
                warning(paste("Failed to process", city, "version", v, ":", cond$message))
            }
        )

        if (exists("osm")) rm(osm)
        if (exists("cycle_net")) rm(cycle_net)
        gc()

        # Cleanup intermediate GPKGs that oe_read() creates as a conversion cache.
        # oe_read names the GPKG from the source PBF stem:
        #   cropped file: city_lower_vshort.gpkg  (in city_dir or osm_raw_dir)
        #   raw file:     geofabrik_stem-v.gpkg   (in osm_raw_dir)
        #   URL download: stem-v.gpkg             (in osm_raw_dir)
        for (gpkg_candidate in c(
            file.path(city_dir, paste0(city_lower, "_", v_short, ".gpkg")),
            file.path(osm_raw_dir, paste0(city_lower, "_", v_short, ".gpkg")),
            file.path(osm_raw_dir, paste0("geofabrik_", infra_stem, "-", v, ".gpkg")),
            file.path(osm_raw_dir, paste0(infra_stem, "-", v, ".gpkg"))
        )) {
            if (file.exists(gpkg_candidate)) file.remove(gpkg_candidate)
        }
    }
}

cat("Historical cycling infrastructure extraction finished.\n")
