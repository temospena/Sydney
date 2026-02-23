# config.R
# Centralized configuration for the CI pipeline

# Base directory where all city data is stored
# Change this when deploying to the server
data_dir <- path.expand("~/GIS/Sydney/data/test-pipeline")

# List of cities to process
target_cities <- c("Sydney", "Lisbon", "Paris", "Barcelona")

# Years to process (formatted as in filenames/API versions)
years <- c("16", "21", "26")
versions <- c("160101", "210101", "260101")

# Global settings
n_od_pairs <- 20000 # Scaling factor for origins/destinations
java_mem <- "-Xmx64G" # Adjusted to 16GB for server stability, can go higher if needed

# Color scheme for custom CI (shared across plots and maps)
ci_colors <- c(
  "Separated cycling infrastructure" = "#054d05",
  "Painted on-road cycle lane" = "#1A7832",
  "Mixed traffic (motor vehicles with light infra)" = "#AFD4A0",
  "Cycling on pedestrian infrastructure" = "#ebc0d4"
)
