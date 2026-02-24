## R/03_ci_osmactive.R
## Build cycling network using osmactive (keep native categories, no aggregation)
## Output: data/<city_tag>/cycling_network_osmactive_<version>.gpkg

build_cycling_osmactive <- function(version = snapshot_version, overwrite = FALSE) {
  stopifnot(exists("city_tag", inherits = TRUE), exists("infra_region", inherits = TRUE))
  
  city_dir <- file.path("data", city_tag)
  if (!dir.exists(city_dir)) dir.create(city_dir, recursive = TRUE)
  
  perim_path <- file.path(city_dir, paste0(city_tag, "_perimeter.gpkg"))
  if (!file.exists(perim_path)) stop("Missing perimeter: ", perim_path, " (run 01_get_boundaries.R)")
  
  perim <- sf::st_read(perim_path, layer = "perimeter", quiet = TRUE) |>
    sf::st_make_valid()
  
  gt <- unique(sf::st_geometry_type(perim))
  if (!any(gt %in% c("POLYGON", "MULTIPOLYGON"))) {
    stop("Perimeter geometry is not polygon. It is: ", paste(gt, collapse = ", "),
         ". Rebuild the perimeter file with force = TRUE.")
  }
  if (sf::st_crs(perim)$epsg != 4326) perim <- sf::st_transform(perim, 4326)
  
  out_path <- file.path(city_dir, paste0(city_tag, "_ci_osmactive_", version, ".gpkg"))
  if (file.exists(out_path) && !overwrite) return(invisible(out_path))
  
  osm <- osmactive::get_travel_network(
    place         = infra_region,
    boundary      = perim,
    boundary_type = "clipsrc",
    version       = version,
    quiet         = FALSE
  )
  
  cycle_net <- osmactive::get_cycling_network(osm)
  drive_net <- osmactive::get_driving_network(osm)
  
  cycle_net <- osmactive::distance_to_road(cycle_net, drive_net)
  cycle_net <- osmactive::classify_cycle_infrastructure(cycle_net, include_mixed_traffic = FALSE)
  
  cycle_net <- cycle_net |>
    dplyr::mutate(infra5 = as.character(cycle_segregation)) |>
    sf::st_transform(4326)
  
  sf::st_write(cycle_net, out_path, driver = "GPKG", append = FALSE, quiet = TRUE)
  invisible(out_path)
}

# Optional auto-run
if (exists("VERSIONS", inherits = TRUE)) {
  for (v in VERSIONS) build_cycling_osmactive(version = v, overwrite = FORCE_BUILD)
}
