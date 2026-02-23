# config.R
# Centralized configuration for the CI pipeline

# Base directory where all city data is stored
# Updated to match server mount point
data_dir <- "/media/rosa/Dados/GIS/Sydney/data/test-pipeline"

# Directory to cache large Geofabrik PBF files (shared across cities)
osm_raw_dir <- "/home/rosa/GIS/osm_raw_cache"

# List of cities to process
if (!exists("target_cities") || length(target_cities) == 0) {
  target_cities <- c("Sydney", "Lisbon", "Paris", "Barcelona")
}

# Map of cities to the most specific Geofabrik region available
region_map <- list(
    Lisbon = "portugal",
    Sydney = "australia/new-south-wales",
    Paris = "france/ile-de-france",
    Barcelona = "spain/cataluna"
)

# Years to process
if (!exists("years")) years <- c("16", "21", "26")
if (!exists("versions")) versions <- c("160101", "210101", "260101")

# Global settings
n_od_pairs <- 20000 
java_mem <- "-Xmx96G" 

# Color scheme for custom CI (shared across plots and maps)
ci_colors <- c(
  "Separated cycling infrastructure" = "#054d05",
  "Painted on-road cycle lane" = "#1A7832",
  "Mixed traffic (motor vehicles with light infra)" = "#AFD4A0",
  "Cycling on pedestrian infrastructure" = "#ebc0d4"
)
