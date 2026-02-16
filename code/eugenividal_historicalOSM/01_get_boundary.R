## R/01_get_boundary.R
## Create + save the city perimeter from OSM.
## Behaviour:
## - If data/<city_tag>/<city_tag>_perimeter.gpkg already exists: do nothing!!!
## - Otherwise: download boundary, build perimeter, write gpkg (layer = "perimeter").
##
## Requires (from R/00_setup.R):
## city_name, city_tag, city_boundary_place

# lisbon city limit
municipios = readRDS(url("https://github.com/U-Shift/SiteSelection/releases/download/0.1/MUNICIPIOSgeo.Rds"))
lisboa = municipios |> filter(Concelho == "Lisboa") |> st_transform(4326)
st_write(lisboa, "data/lisbon/lisbon_perimeter.gpkg", layer = "perimeter", append = FALSE, quiet = TRUE)


# sydney - region?
sydnet_sur = st_read("transit/Sydney_and_surrounds.json")
table(sydnet_sur$NSW_LGA__3)
mapview(sydnet_sur)

inner_central = c("SYDNEY", "INNER WEST", "RANDWICK", "BAYSIDE")
north = c("NORTHERN BEACHES", "NORTH SYDNEY", "HORNSBY")
west_southwest = c("PARRAMATTA", "BLACKTOWN", "PENRITH", "CAMPBELLTOWN")

sydney_area = sydnet_sur |> filter(NSW_LGA__3 %in% c(inner_central, north, west_southwest))
mapview::mapview(sydney_area)

# see https://www.planning.nsw.gov.au/sites/default/files/2023-03/metropolitan-boundaries-map.pdf


sydney_city = st_write(sydnet_sur |> filter(NSW_LGA__3 == "SYDNEY"), "data/sydney/sydney_perimeter.gpkg", layer = "perimeter", append = FALSE, quiet = TRUE)

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
city_dir <- file.path("data", city_tag)
dir.create(city_dir, showWarnings = FALSE, recursive = TRUE)

out_gpkg <- file.path(city_dir, paste0(city_tag, "_perimeter.gpkg"))

# ------------------------------------------------------------
# Skip if already exists
# ------------------------------------------------------------
if (file.exists(out_gpkg)) {
  message("Skip: perimeter already exists -> ", out_gpkg)
  # Optional: read once to ensure it is readable/valid (comment out if you truly want zero work)
  invisible(sf::st_read(out_gpkg, layer = "perimeter", quiet = TRUE))
} else {
  
  # 1) Get bbox for the place
  bbox <- osmdata::getbb(city_boundary_place, format_out = "polygon")
  if (is.null(bbox)) stop("Bounding box not found for: ", city_boundary_place)
  
  # 2) Query admin boundary (municipality level)
  b <- osmdata::opq(bbox = bbox) |>
    osmdata::add_osm_feature(key = "boundary", value = "administrative") |>
    osmdata::add_osm_feature(key = "admin_level", value = "8") |>
    osmdata::osmdata_sf()
  
  mp <- b$osm_multipolygons
  if (is.null(mp) || !nrow(mp)) stop("No admin multipolygons found for: ", city_boundary_place)
  
  # 3) IMPORTANT: ensure sf knows which column is geometry (fixes sf_column error)
  geom_cols <- names(mp)[vapply(mp, inherits, logical(1), "sfc")]
  if (!length(geom_cols)) stop("No geometry column found in osm_multipolygons.")
  sf::st_geometry(mp) <- geom_cols[1]
  
  # 4) Pick best matching feature by name
  nm <- tolower(city_name)
  mp$.__name__ <- tolower(as.character(mp$name))
  cand <- mp[grepl(nm, mp$.__name__, fixed = TRUE), , drop = FALSE]
  if (!nrow(cand)) cand <- mp
  
  # Reset geometry after subsetting (can matter)
  geom_cols2 <- names(cand)[vapply(cand, inherits, logical(1), "sfc")]
  sf::st_geometry(cand) <- geom_cols2[1]
  
  # 5) Union to single geometry + validate + cast + set CRS
  perim <- sf::st_make_valid(cand) |>
    sf::st_union() |>
    sf::st_make_valid() |>
    sf::st_cast("MULTIPOLYGON")
  
  perim <- sf::st_as_sf(perim)
  sf::st_crs(perim) <- 4326
  perim <- sf::st_transform(perim, 4326)
  
  # 6) Write gpkg with stable layer name
  sf::st_write(perim, out_gpkg, layer = "perimeter", driver = "GPKG",
               append = FALSE, quiet = TRUE)
  
  message("Saved perimeter for ", city_name, " -> ", out_gpkg)
  invisible(perim)
}
