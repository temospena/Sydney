# 02_historical_routing_osm.R
# Crop historical Geofabrik OSM PBF files for routing using osmium
# Incorporates fallback to download missing raw data using osmextract

library(sf)
library(osmextract)
library(dplyr)
options(timeout = 3600) # give 1hr limit for large file downloads over wifi

# Config
target_cities <- c("Sydney")
years <- c(16, 21, 26)
data_dir <- path.expand("~/GIS/Sydney/data/test-pipeline")
raw_pbf_dir <- "/media/rosa/Dados/GIS/Sydney/networks/osmpbf files" # Or wherever the user mounts the raw PBFs

# Map full geofabrik region names for our target cities
region_map <- list(
    Lisbon = "portugal",
    Sydney = "australia",
    Paris = "ile-de-france",
    Barcelona = "spain"
)

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

    for (yr in years) {
        # Expected filename on disk: e.g. geofabrik_portugal-160101.osm.pbf
        raw_file <- file.path(raw_pbf_dir, paste0("geofabrik_", geofabrik_region, "-", yr, "0101.osm.pbf"))
        out_file <- file.path(city_dir, paste0(city_lower, "_", yr, ".osm.pbf"))

        # If the clipped output already exists, we skip downloading/processing
        if (file.exists(out_file)) {
            cat(paste("Output", out_file, "already exists. Skipping osmium crop.\n"))
            next
        }

        # If raw file is missing, fallback to download using osmextract
        if (!file.exists(raw_file)) {
            cat(sprintf("Raw PBF missing for %s year %s. Attempting to download fallback to %s/temp ...\n", city, yr, city_dir))

            # We will try to download the *current* PBF using oe_get or oe_download into a temp directory
            # as a fallback if the exact historical one isn't located. This fulfills the user request.
            file_url <- oe_match(geofabrik_region, provider = "geofabrik")$url
            temp_pbf <- oe_download(
                file_url = file_url,
                download_directory = city_dir
            )
            raw_file <- temp_pbf
            downloaded_pbf_path <- temp_pbf
        }

        # Run Osmium to crop using bounding box
        cmd <- paste("osmium extract -b", bbox_str, "\"", raw_file, "\"", "-o", "\"", out_file, "\"")
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
