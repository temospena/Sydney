# 02_historical_routing_osm.R
# Crop historical Geofabrik OSM PBF files for routing using osmium
# Incorporates fallback to download missing raw data using osmextract

library(sf)
library(osmextract)
library(dplyr)
options(timeout = 3600) # give 1hr limit for large file downloads over wifi

# Load global configuration
source("code/test-pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run
raw_pbf_dir <- osm_raw_dir

cat("Starting OSMIUM cropping for routing files...\n")

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)

    # Read bbox
    bbox_path <- file.path(city_dir, paste0(city_lower, "_bbox.txt"))
    if (!file.exists(bbox_path)) {
        warning(paste("Missing bbox file for", city, "- Skipping..."))
        next
    }

    bbox_str <- readLines(bbox_path, warn = FALSE)
    geofabrik_region <- region_map[[city]]
    downloaded_pbf_path <- NULL

    # Sanitize region for filename
    safe_region <- gsub("/", "_", geofabrik_region)

    for (yr in years) {
        # Expected filename on disk: e.g. geofabrik_portugal-160101.osm.pbf
        raw_file <- file.path(raw_pbf_dir, paste0("geofabrik_", safe_region, "-", yr, "0101.osm.pbf"))
        local_cache_file <- file.path(city_dir, paste0("geofabrik_", safe_region, "-", yr, "0101.osm.pbf"))

        if (!file.exists(raw_file) && file.exists(local_cache_file)) {
            raw_file <- local_cache_file
        }

        out_file <- file.path(city_dir, paste0(city_lower, "_", yr, ".osm.pbf"))

        # If the clipped output already exists, we skip downloading/processing unless FORCE_RERUN is TRUE
        if (file.exists(out_file)) {
            if (FORCE_RERUN) {
                cat(paste("  [FORCING RE-CROP] Output", out_file, "exists but FORCE_RERUN is TRUE.\n"))
            } else {
                cat(paste("  [SKIPPING] Output", out_file, "already exists. Set FORCE_RERUN <- TRUE in config.R to overwrite.\n"))
                next
            }
        }

        # If raw file is missing, fallback to download using osmextract
        if (!file.exists(raw_file)) {
            cat(sprintf("!!! [MISSING HISTORICAL DATA] Raw PBF missing for %s year %s. !!!\n", city, yr))
            
            # Critical fix: If we don't have historical data, using 'latest' for 2016 is wrong.
            # We will attempt to forceoe_download to find a match.
            cat("Attempting to download best match from Geofabrik...\n")
            
            temp_pbf <- tryCatch({
              oe_download(
                  file_url = geofabrik_region,
                  provider = "geofabrik",
                  download_directory = raw_pbf_dir, # Download to shared cache!
                  quiet = FALSE
              )
            }, error = function(e) {
              cat("  Geofabrik download failed, falling back to any available provider...\n")
              oe_download(file_url = geofabrik_region, download_directory = raw_pbf_dir)
            })
            
            raw_file <- temp_pbf
            downloaded_pbf_path <- temp_pbf
            
            # Check if what we downloaded is actually the current one (no date in filename)
            if (!grepl(paste0("-", yr), basename(raw_file))) {
                cat("  [WARNING]: Using LATEST map for historical year", yr, ". This will result in 0% routing change!\n")
            }
        }

        # Run Osmium to crop using bounding box
        cmd <- sprintf("osmium extract -b %s \"%s\" -o \"%s\"", bbox_str, raw_file, out_file)
        cat("Running OSMIUM:", cmd, "\n")

        sys_res <- system(cmd, intern = FALSE)
        if (sys_res == 0) {
            cat(paste("Successfully cropped", out_file, "\n"))
        } else {
            warning(paste("Osmium failed for", city, "year", yr))
        }
    }

    # Cleanup the downloaded huge file if we had to download it temporarily
    if (!is.null(downloaded_pbf_path) && file.exists(downloaded_pbf_path)) {
        cat("Cleaning up temporarily downloaded large raw PBF file...\n")
        unlink(downloaded_pbf_path)
    }
}

cat("Historical routing OSM cropping logic finished.\n")
