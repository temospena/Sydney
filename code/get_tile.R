library(sf)
sf_use_s2(TRUE)
lod1 <- st_read("data/lod1.geojson", quiet = TRUE)
target_cities <- c("Lisbon", "Sydney", "Paris", "Barcelona")
tile_map <- list()

for (city in target_cities) {
  city_lower <- tolower(city)
  poly_path <- file.path("data/test-pipeline", city_lower, paste0(city_lower, "_10km.gpkg"))
  if (file.exists(poly_path)) {
    poly <- st_read(poly_path, quiet = TRUE)
    intersects <- st_intersects(poly, lod1, sparse = FALSE)
    intersecting_tiles <- lod1[intersects[1, ], ]$tile
    if (length(intersecting_tiles) > 0) {
      # Take first intersecting tile and remove the region prefix (e.g., 'europe/')
      tile_map[[city]] <- sub("^.*/", "", intersecting_tiles[1])
    }
  }
}
print(tile_map)
