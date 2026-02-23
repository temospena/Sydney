# crop osm.pbf with osmium

# check bboxes

library(sf)
library(mapview)

# --- 1. Define the Bounding Boxes ---
# Coordinates: Left (min_lon), Bottom (min_lat), Right (max_lon), Top (max_lat)

bboxes <- list(
  Lisbon = c(-9.50, 38.40, -8.70, 39.10),
  Sydney = c(150.50, -34.15, 151.35, -33.55),
  Paris = c(2.21,48.81,2.47,48.91)
)

# --- 2. Function to convert coords to a Polygon ---
create_bbox_poly <- function(coords, label) {
  # Create a matrix of the 5 points needed to close a square
  mat <- matrix(c(
    coords[1], coords[2], # Bottom-Left
    coords[3], coords[2], # Bottom-Right
    coords[3], coords[4], # Top-Right
    coords[1], coords[4], # Top-Left
    coords[1], coords[2]  # Close back at Bottom-Left
  ), ncol = 2, byrow = TRUE)
  
  st_sfc(st_polygon(list(mat)), crs = 4326) %>%
    st_sf(City = label, row.names = label)
}

# --- 3. Generate Polygons ---
lisbon_poly <- create_bbox_poly(bboxes$Lisbon, "Lisbon Metro Area")
sydney_poly <- create_bbox_poly(bboxes$Sydney, "Sydney Metro Area")
paris_poly <- create_bbox_poly(bboxes$Paris, "Paris city Area")

# --- 4. Visualize with Mapview ---
# You can view them one by one or together
mapview(lisbon_poly, color = "red", col.regions = "red", alpha.regions = 0.2)
mapview(sydney_poly, color = "blue", col.regions = "blue", alpha.regions = 0.2)
mapview(paris_poly, color = "darkgreen", col.regions = "darkgreen", alpha.regions = 0.2)



# no cli sh - see crop_osm_pbf_bbox.sh ------------------------------------------------------------------
# replace the bbox coords
# rosa@rosa-ist: cd /media/rosa/Dados/GIS/Sydney/networks/osmpbf files
# osmium extract -b -9.50,38.40,-8.70,39.10 geofabrik_portugal-160101.osm.pbf -o lisbon_metro_16.pbf
# osmium extract -b -9.50,38.40,-8.70,39.10 geofabrik_portugal-210101.osm.pbf -o lisbon_metro_21.pbf
# osmium extract -b -9.50,38.40,-8.70,39.10 geofabrik_portugal-260101.osm.pbf -o lisbon_metro_26.pbf
# 
# osmium extract -b 150.50,-34.15,151.35,-33.55 geofabrik_australia-160101.osm.pbf -o sydney_metro_16.pbf
# osmium extract -b 150.50,-34.15,151.35,-33.55 geofabrik_australia-210101.osm.pbf -o sydney_metro_21.pbf
# osmium extract -b 150.50,-34.15,151.35,-33.55 geofabrik_australia-260101.osm.pbf -o sydney_metro_26.pbf
# 
# osmium extract -b 2.21,48.81,2.47,48.91 geofabrik_ile-de-france-160101.osm.pbf -o paris_city_16.pbf
# osmium extract -b 2.21,48.81,2.47,48.91 geofabrik_ile-de-france-210101.osm.pbf -o paris_city_21.pbf
# osmium extract -b 2.21,48.81,2.47,48.91 geofabrik_ile-de-france-260101.osm.pbf -o paris_city_26.pbf