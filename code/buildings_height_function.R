# Extract buildings height and estimate floors from the Global Building Atlas LOD1 dataset using DuckDB and sf
# https://mediatum.ub.tum.de/1782307
# https://source.coop/tge-labs/globalbuildingatlas-lod1
# cite: https://doi.org/10.5194/essd-17-6647-2025

library(duckdb)
library(sf)
library(dplyr)


fetch_building_points <- function(city_name, bbox_list, parket_file_dir) {
  
  parquet_s3_path <- paste0("s3://us-west-2.opendata.source.coop/tge-labs/globalbuildingatlas-lod1/", parket_file_dir, ".parquet")
  
  
  # 1. Extract coordinates from list
  coords <- bbox_list[[city_name]]
  if(is.null(coords)) stop("City not found in list!")
  
  # Map variables for the SQL query
  # Note: your list format is xmin, ymin, xmax, ymax
  q_xmin <- coords[1]; q_ymin <- coords[2]; q_xmax <- coords[3]; q_ymax <- coords[4]
  
  # 2. Setup DuckDB
  con <- dbConnect(duckdb())
  dbExecute(con, "INSTALL spatial; LOAD spatial; INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2'; SET preserve_insertion_order=false;")
  
  # 3. Query using BBox midpoints (Fastest & most stable)
  query <- paste0("
    SELECT * EXCLUDE (geometry), 
           ST_AsWKB(TRY_CAST(geometry AS GEOMETRY)) as geom_wkb
    FROM read_parquet('", parquet_s3_path, "')
    WHERE bbox.xmin >= ", q_xmin, " AND bbox.xmax <= ", q_xmax, "
      AND bbox.ymin >= ", q_ymin, " AND bbox.ymax <= ", q_ymax
      )
  
  
  message(paste("Fetching data for", city_name, "..."))
  raw_data <- dbGetQuery(con, query) |> 
    filter(!is.na(geom_wkb)) # Remove the NULLs we created
  dbDisconnect(con) # STOP the connection to free resources
  
  if (nrow(raw_data) == 0) {
    message("No buildings found for this area.")
    return(NULL)
  }
  
  # 4. Transform to SF points
  buildings_centroids <- raw_data %>%
    filter(!is.na(geom_wkb)) %>% # remove non-geometric entries
    mutate(geometry = st_as_sfc(geom_wkb, crs = 4326)) %>%  # Convert to sf object so st_area works correctly
    st_as_sf() %>%
    mutate(
      # Transform to metric (3857) to get area in square meters
      footprint_m2 = round(as.numeric(st_area(st_transform(., 3857)))), #A0
      est_floors = pmax(1, round(height / 3)), # average 3m height per floor, with a minimum of 1 flooror
      total_floor_area_m2 = round(footprint_m2 * est_floors), # ABC
      # Midpoints for the final point geometry
      lon = (bbox$xmin + bbox$xmax) / 2,
      lat = (bbox$ymin + bbox$ymax) / 2
    ) %>%
    # Convert polygons to points using the midpoints calculated
    st_drop_geometry() %>% 
    st_as_sf(coords = c("lon", "lat"), crs = 4326) %>%
    select(source, id, height, var, est_floors, footprint_m2, total_floor_area_m2)
  
  return(buildings_centroids)
}


# run ---------------------------------------------------------------------
# See in the 
# datalod1 = st_read("data/lod1.geojson")
#### SEE HERE: https://source.coop/tge-labs/globalbuildingatlas-lod1
lisbon_file_dir = "w010_n40_w005_n35" # Lisbon
sydney_file_dir = "e150_s30_e155_s35" # Sydney
paris_file_dir = "e000_n50_e005_n45" # Paris
barcelona_file_dir = "e000_n45_e005_n40" # Barcelona

bboxes <- list(
  Lisbon = c(-9.50, 38.40, -8.70, 39.10),
  Sydney = c(150.50, -34.15, 151.35, -33.55),
  Paris = c(2.21, 48.81, 2.47, 48.91),
  Barcelona = c(2.01, 41.30, 2.24, 41.49)
)
bboxes = readRDS("data/bboxes.rds")

lisbon_buildings <- fetch_building_points("Lisbon", bboxes, lisbon_file_dir)
sydney_buildings <- fetch_building_points("Sydney", bboxes, sydney_file_dir)
paris_buildings <- fetch_building_points("Paris", bboxes, paris_file_dir)
barcelona_buildings <- fetch_building_points("Barcelona", bboxes, barcelona_file_dir)

st_write(lisbon_buildings, "data/lisbon/lisbon_metro_buildings_height.geojson", delete_dsn = TRUE)
st_write(sydney_buildings, "data/sydney/sydney_metro_buildings_height.geojson", delete_dsn = TRUE)
st_write(paris_buildings, "data/paris/paris_metro_buildings_height.geojson", delete_dsn = TRUE)
st_write(barcelona_buildings, "data/barcelona/barcelona_metro_buildings_height.geojson", delete_dsn = TRUE) # not metro!

summary(lisbon_buildings$est_floor) # median: 1, mean: 1.64
summary(sydney_buildings$est_floor) # median: 2; mean: 1.95
summary(paris_buildings$est_floor) # median: 3; mean: 2.92
summary(barcelona_buildings$est_floor) # median: 4; mean: 3.773 (this is the city bbox, not the region) 



lisbon_buildings_city = lisbon_buildings[lisboa,] # spatial filter
paris_buildings_city = paris_buildings[paris_lim, ]
sydney_buildings_city = sydney_buildings[sydney_city |> st_make_valid(), ]
barcelona_buildings_city = barcelona_buildings[barcelona_perim, ]

summary(lisbon_buildings_city$est_floor) # median: 3, mean: 2.94
summary(paris_buildings_city$est_floor) # median: 4; mean: 3.92
summary(sydney_buildings_city$est_floor) # median: 3; mean: 3.21
summary(barcelona_buildings_city$est_floor) # median: 4; mean: 4.57


summary(lisbon_buildings_city$total_floor_area_m2) # median: 752, mean: 4803
summary(paris_buildings_city$total_floor_area_m2) # median: 1588; mean: 3452
summary(sydney_buildings_city$total_floor_area_m2) # median: 804; mean: 3563
summary(barcelona_buildings_city$total_floor_area_m2) # median: 1350; mean: 3697

sf::st_write(lisbon_buildings_city, "data/lisbon/lisbon_city_buildings.geojson")
sf::st_write(paris_buildings_city, "data/paris/paris_city_buildings.geojson")
sf::st_write(sydney_buildings_city, "data/sydney/sydney_city_buildings.geojson")
sf::st_write(barcelona_buildings_city, "data/barcelona/barcelona_city_buildings.geojson")


# map ---------------------------------------------------------------------

library(mapview)
library(RColorBrewer)

mapview(lisbon_buildings_city, 
              zcol = "est_floors", # flors
              # zcol = "total_floor_area_m2", # area
              # cex = "est_floors",       # Size of the dots based on floors
               cex = 0.6, # fixed size
              col.regions = colorRampPalette(brewer.pal(9, "YlOrRd")),        # Our custom color palette
              alpha.regions = 0.7,      # Slight transparency to see overlapping points
              alpha = 0, # hide limit
              layer.name = "Est. Floors",
              map.types = c("CartoDB.DarkMatter", "OpenStreetMap", "Esri.WorldImagery"),
              legend = TRUE)


# upload to github --------------------------------------------------------


piggyback::pb_upload("data/lisbon/lisbon_metro_buildings_height.geojson")
piggyback::pb_upload("data/sydney/sydney_metro_buildings_height.geojson")
piggyback::pb_upload("data/paris/paris_metro_buildings_height.geojson")
piggyback::pb_upload("data/barcelona/barcelona_metro_buildings_height.geojson")

piggyback::pb_upload("data/lisbon/lisbon_city_buildings.geojson")
piggyback::pb_upload("data/sydney/sydney_city_buildings.geojson")
piggyback::pb_upload("data/paris/paris_city_buildings.geojson")
piggyback::pb_upload("data/barcelona/barcelona_city_buildings.geojson")
