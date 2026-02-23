# config.R
# Centralized configuration for the CI pipeline

# Base directory where all city data is stored
# Using here() but ensuring we handle the media drive mount correctly
if (requireNamespace("here", quietly = TRUE)) {
  # If we are running from the media drive, use the current working directory as the root
  proj_root <- here::here()
  if (!grepl("media", proj_root) && grepl("media", getwd())) proj_root <- getwd()
  
  data_dir <- file.path(proj_root, "data/test-pipeline")
  osm_raw_dir <- file.path(dirname(proj_root), "osm_raw_cache")
} else {
  data_dir <- "data/test-pipeline"
  osm_raw_dir <- "../osm_raw_cache"
}
cat("[DEBUG] Working Directory:", getwd(), "\n")
cat("[DEBUG] Data Directory:", data_dir, "\n")

# List of cities to process
if (!exists("target_cities") || length(target_cities) == 0) {
  # Sydney is excluded as it was already processed successfully
  target_cities <- c("Lisbon", "Paris", "Barcelona")
}

# Map of cities to the Geofabrik region name
region_map <- list(
    Lisbon = "portugal",
    Sydney = "new-south-wales",
    Paris = "ile-de-france",
    Barcelona = "cataluna"
)

# Years to process
if (!exists("years")) years <- c("16", "21", "26")
if (!exists("versions")) versions <- c("160101", "210101", "260101")

# Routing Settings
n_od_pairs <- 20000 
java_mem <- "-Xmx96G" 
if (!exists("FORCE_RERUN")) FORCE_RERUN <- FALSE # Set to TRUE to bypass all skip logic
cat("[CONFIG] FORCE_RERUN is currently:", FORCE_RERUN, "\n")

# Color scheme for custom CI (shared across plots and maps)
ci_colors <- c(
  "Separated cycling infrastructure" = "#054d05",
  "Painted on-road cycle lane" = "#1A7832",
  "Mixed traffic (motor vehicles with light infra)" = "#AFD4A0",
  "Cycling on pedestrian infrastructure" = "#ebc0d4"
)
