# Install necessary packages if you don't have them
# install.packages(c("duckdb", "sf", "dplyr"))
library(duckdb)
library(sf)
library(dplyr)

# 1. Setup Connection
con <- dbConnect(duckdb())
dbExecute(con, "INSTALL spatial; LOAD spatial;")
dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
# This allows DuckDB to read from S3/HTTP URLs
dbExecute(con, "SET s3_region='us-west-2';") 
dbExecute(con, "SET preserve_insertion_order=false;")
# dbExecute(con, "SET memory_limit='4GB';") # Limits RAM usage so your PC stays responsive

# 2. Targeted BBox 
# (Broad enough to capture the city, small enough for speed)
xmin <- -9.50; ymin <- 38.40; xmax <- -9.05; ymax <- 38.85



parket_file_dir = "w010_n40_w005_n35" # Lisbon
#### SEE HERE: https://source.coop/tge-labs/globalbuildingatlas-lod1

# 3. Set the Direct URL
parquet_url <- "https://source.coop/tge-labs/globalbuildingatlas-lod1/w010_n40_w005_n35.parquet"
parquet_s3_path <- paste0("s3://us-west-2.opendata.source.coop/tge-labs/globalbuildingatlas-lod1/", parket_file_dir, ".parquet")



# 4. Corrected Query with Explicit Casting
# We cast the 'geometry' column to BLOB so ST_GeomFromWKB recognizes it
# Improved Query with Error Handling (TRY_ST_GeomFromWKB)

query <- paste0("
  SELECT * EXCLUDE (geometry), 
         TRY_CAST(geometry AS GEOMETRY) as geom
  FROM read_parquet('", parquet_s3_path, "')
  WHERE bbox.xmin >= ", xmin, " AND bbox.xmax <= ", xmax, "
    AND bbox.ymin >= ", ymin, " AND bbox.ymax <= ", ymax
)


# 4. Fetch the data
# Use dbGetQuery for SELECT statements
raw_data <- dbGetQuery(con, query) |> 
  filter(!is.na(geom)) # Remove the NULLs we created

### STOP connection
dbDisconnect(con)

# Convert to jeojson with floors ------------------------------------------

# 1. Convert the raw data to an 'sf' object (Polygons)
# DuckDB returns geom as a list of raw bytes; st_as_sfc handles the conversion
building_centroids <- raw_data %>%
  mutate(     # Simple mid-point calculation
    lon = (bbox$xmin + bbox$xmax) / 2,
    lat = (bbox$ymin + bbox$ymax) / 2,
    est_floors = pmax(1, round(height / 3))) |>  #estimated floors calculation
  st_as_sf(coords = c("lon", "lat"), crs = 4326) |> 
  select(source, id, height, var, est_floors)

# 4. Export to GeoJSON
st_write(building_centroids, "data/lisbon/lisbon_building_centroids.geojson", delete_dsn = TRUE)

# Optional: Preview the data
print(head(building_centroids))


# map ---------------------------------------------------------------------

library(mapview)
library(RColorBrewer)

# 1. Prepare the data for visualization
# We'll create a color palette: Green for low-rise, Yellow for mid, Red for high-rise
pal <- colorRampPalette(brewer.pal(9, "YlOrRd"))

# 2. Create the Mapview
# 'zcol' defines the color attribute
# 'cex' defines the circle size (scaled by floor count)
mv <- mapview(building_centroids, 
              zcol = "est_floors", 
              cex = "est_floors",       # Size of the dots based on floors
              col.regions = pal,        # Our custom color palette
              alpha.regions = 0.7,      # Slight transparency to see overlapping points
              layer.name = "Est. Floors (Lisbon)",
              map.types = c("CartoDB.DarkMatter", "OpenStreetMap", "Esri.WorldImagery"),
              legend = TRUE)

# 3. View the map
mv

