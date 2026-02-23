# config.R
# Centralized configuration for the CI pipeline

# Base directory where all city data is stored
# Using here() for robust relative paths regardless of execution context
if (requireNamespace("here", quietly = TRUE)) {
  data_dir <- here::here("data/test-pipeline")
  osm_raw_dir <- here::here("../osm_raw_cache")
} else {
  data_dir <- "data/test-pipeline"
  osm_raw_dir <- "../osm_raw_cache"
}

# List of cities to process
if (!exists("target_cities") || length(target_cities) == 0) {
  # Sydney is excluded as it was already processed successfully
  target_cities <- c("Lisbon", "Paris", "Barcelona")
}

# Map of cities to the most specific Geofabrik region available
region_map <- list(
    Lisbon = "europe/portugal",
    Sydney = "australia/new-south-wales",
    Paris = "europe/france/ile-de-france",
    Barcelona = "europe/spain/cataluna"
)

# Years to process
if (!exists("years")) years <- c("16", "21", "26")
if (!exists("versions")) versions <- c("160101", "210101", "260101")

# Routing Settings
n_od_pairs <- 20000 
java_mem <- "-Xmx96G" 
FORCE_RERUN <- FALSE # Set to TRUE to bypass all skip logic and force a fresh run

# Color scheme for custom CI (shared across plots and maps)
ci_colors <- c(
  "Separated cycling infrastructure" = "#054d05",
  "Painted on-road cycle lane" = "#1A7832",
  "Mixed traffic (motor vehicles with light infra)" = "#AFD4A0",
  "Cycling on pedestrian infrastructure" = "#ebc0d4"
)
