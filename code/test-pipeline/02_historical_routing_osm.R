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

        # If raw file is missing, attempt strict historical download
        if (!file.exists(raw_file)) {
            cat(sprintf("!!! [MISSING HISTORICAL DATA] Raw PBF missing for %s year %s. !!!\n", city, yr))
            
            # Smart Discovery: Use oe_match to find the continent and base URL
            match_res <- tryCatch({
              oe_match(geofabrik_region, provider = "geofabrik")
            }, error = function(e) {
                # Try fallback names if specific region fails
                if (geofabrik_region == "cataluna") return(oe_match("spain", provider = "geofabrik"))
                return(NULL)
            })
            
            if (is.null(match_res)) {
              stop(sprintf("CRITICAL ERROR: Region '%s' not found on Geofabrik.", geofabrik_region))
            }
            
            # Construct archive URL by replacing '-latest' with our target date
            # Geofabrik archive format: https://download.geofabrik.de/europe/portugal-160101.osm.pbf
            archive_url <- gsub("-latest.osm.pbf", paste0("-", yr, "0101.osm.pbf"), match_res$url)
            
            cat("Attempting to fetch historical archive from Discovery URL:", archive_url, "\n")
            
            download_success <- tryCatch({
              oe_download(file_url = archive_url, download_directory = raw_pbf_dir, quiet = FALSE)
              TRUE
            }, error = function(e) {
              cat("  [FAIL] Historical file not found in public Geofabrik archive.\n")
              FALSE
            })
            
            if (!download_success) {
                stop(sprintf("\nCRITICAL ERROR: No historical PBF found for %s year %s.\nTo fix this:\n1. Manually download the PBF for this date.\n2. Place it here: %s\n3. Rename it to: %s\n", 
                             city, yr, raw_pbf_dir, basename(raw_file)))
            }
            
            # Update path once downloaded
            raw_file <- file.path(raw_pbf_dir, paste0("geofabrik_", safe_region, "-", yr, "0101.osm.pbf"))
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
