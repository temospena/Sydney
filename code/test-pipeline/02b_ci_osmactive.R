# 02b_ci_osmactive.R
# Extract historical cycling network infrastructure using osmactive

library(osmactive)
library(sf)
library(dplyr)
sf_use_s2(TRUE)
options(timeout = 3600)

data_dir <- path.expand("~/GIS/Sydney/data/test-pipeline")
target_cities <- c("Sydney")
# osmactive historical versions correspond to YYMMDD strings, like "160101"
versions <- c("160101", "210101", "260101")

# Geofabrik matched names
region_map <- list(
    Lisbon = "portugal",
    Sydney = "australia",
    Paris = "ile-de-france",
    Barcelona = "spain"
)

for (city in target_cities) {
    city_lower <- tolower(city)
    city_dir <- file.path(data_dir, city_lower)

    # Load the generated 10km buffer to act as the extraction boundary
    perim_path <- file.path(city_dir, paste0(city_lower, "_10km.gpkg"))
    if (!file.exists(perim_path)) {
        warning(paste("Missing perimeter for", city, "- Skipping..."))
        next
    }

    perim <- sf::st_read(perim_path, quiet = TRUE) |> sf::st_make_valid()
    if (sf::st_crs(perim)$epsg != 4326) perim <- sf::st_transform(perim, 4326)

    infra_region <- region_map[[city]]

    for (v in versions) {
        out_path <- file.path(city_dir, paste0(city_lower, "_ci_osmactive_", v, ".gpkg"))

        if (file.exists(out_path)) {
            message("Skipping already generated CI for", city, "version", v)
            next
        }

        cat(paste("Extracting CI for", city, "version", v, "...\n"))

        # Needs internet connection and enough RAM
        tryCatch(
            {
                osm <- osmactive::get_travel_network(
                    place = infra_region,
                    boundary = perim,
                    boundary_type = "clipsrc",
                    version = v,
                    download_directory = city_dir,
                    quiet = FALSE
                )

                cycle_net <- osmactive::get_cycling_network(osm)
                drive_net <- osmactive::get_driving_network(osm)

                cycle_net <- osmactive::distance_to_road(cycle_net, drive_net)
                cycle_net <- osmactive::classify_cycle_infrastructure(cycle_net, include_mixed_traffic = FALSE)

                cycle_net <- cycle_net |>
                    dplyr::mutate(infra5 = as.character(cycle_segregation)) |>
                    sf::st_transform(4326)

                sf::st_write(cycle_net, out_path, driver = "GPKG", append = FALSE, quiet = TRUE)
                cat(paste("Successfully saved", out_path, "\n"))
            },
            error = function(cond) {
                warning(paste("Failed to process", city, "version", v, ":", cond$message))
            }
        )

        # Cleanup memory
        if (exists("osm")) rm(osm)
        if (exists("cycle_net")) rm(cycle_net)
        if (exists("drive_net")) rm(drive_net)
        gc()
    }
}

cat("Historical cycling infrastructure extraction finished.\n")
