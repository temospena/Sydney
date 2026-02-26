# config.R
# Centralized configuration for the CI pipeline

# Base directory where all city data is stored
# Using here() but ensuring we handle the media drive mount correctly
if (requireNamespace("here", quietly = TRUE)) {
  # If we are running from the media drive, use the current working directory as the root
  proj_root <- here::here()
  if (!grepl("media", proj_root) && grepl("media", getwd())) proj_root <- getwd()

  data_dir <- file.path(proj_root, "data/pipeline")
  osm_raw_dir <- file.path(proj_root, "data/osm_pbf")
} else {
  data_dir <- "data/pipeline"
  osm_raw_dir <- "data/osm_pbf"
}
cat("[DEBUG] Working Directory:", getwd(), "\n")
cat("[DEBUG] Data Directory:", data_dir, "\n")

# List of cities to process
if (!exists("target_cities") || length(target_cities) == 0) {
  # New requested city batch: Geographically distributed with strong cycling culture
  # target_cities <- c("Milan", "Mexico City", "Bogota", "Montréal", "Minneapolis", "Berlin", "Seville", "Christchurch")
  target_cities = "Seville"
  # target_cities = "Christchurch"
}

# Map of cities to the Geofabrik region name
# (No longer strictly needed since get_geofabrik_url explicitly handles them, but kept for legacy compat)
region_map <- list(
  Lisbon = "portugal",
  Sydney = "australia",
  Paris = "ile-de-france",
  Barcelona = "cataluna",
  Munich = "oberbayern",
  London = "greater-london",
  `New York` = "new-york",
  `Sao Paulo` = "sudeste"
)

# Helper function to get exact Geofabrik URLs as specified by the user
get_geofabrik_url <- function(city, year_short) {
  base_url <- "http://download.geofabrik.de/"
  postfix <- paste0("-", year_short, "0101.osm.pbf")

  # Support lowercase matching
  city_lower <- tolower(city)

  if (city_lower == "sydney") {
    prefix <- "australia-oceania/australia"
  } else if (city_lower == "lisbon") {
    prefix <- "europe/portugal"
  } else if (city_lower == "paris") {
    prefix <- "europe/france/ile-de-france"
  } else if (city_lower == "barcelona") {
    if (as.numeric(year_short) >= 22) {
      prefix <- "europe/spain/cataluna"
    } else {
      prefix <- "europe/spain"
    }
  } else if (city_lower == "munich") {
    prefix <- "europe/germany/bayern/oberbayern"
  } else if (city_lower == "london") {
    prefix <- "europe/united-kingdom/england/greater-london"
  } else if (city_lower == "new york") {
    prefix <- "north-america/us/new-york"
  } else if (city_lower == "sao paulo") {
    if (year_short == "16") {
      prefix <- "south-america/brazil"
    } else {
      prefix <- "south-america/brazil/sudeste"
    }
  } else if (city_lower == "portland") {
    prefix <- "north-america/us/oregon"
  } else if (city_lower == "santiago") {
    prefix <- "south-america/chile"
  } else if (city_lower == "brussels") {
    prefix <- "europe/belgium"
  } else if (city_lower == "vancouver") {
    prefix <- "north-america/canada/british-columbia"
  } else if (city_lower == "tokyo") {
    if (year_short == "16") {
      prefix <- "asia/japan"
    } else {
      prefix <- "asia/japan/kanto"
    }
  } else if (city_lower == "milan") {
    prefix <- "europe/italy/nord-ovest"
  } else if (city_lower == "mexico city") {
    prefix <- "north-america/mexico"
  } else if (city_lower == "bogota") {
    prefix <- "south-america/colombia"
  } else if (city_lower == "montréal") {
    prefix <- "north-america/canada/quebec"
  } else if (city_lower == "minneapolis") {
    prefix <- "north-america/us/minnesota"
  } else if (city_lower == "berlin") {
    prefix <- "europe/germany/berlin"
  } else if (city_lower == "seville") {
    if (as.numeric(year_short) > 21) {
      prefix <- "europe/spain/andalucia"
    } else {
      prefix <- "europe/spain"
    }
  } else if (city_lower == "christchurch") {
    prefix <- "australia-oceania/new-zealand"
  } else {
    stop(paste("No URL mapping found for", city))
  }

  return(paste0(base_url, prefix, postfix))
}

# Helper function to get the region name for filenames based on the URL
# This ensures that if we download 'spain' (for older years), we save it as 'spain'
get_geofabrik_region <- function(city, year_short) {
  url <- get_geofabrik_url(city, year_short)
  # Extract the part after the last / and before the -year0101
  region <- gsub(".*/", "", url)
  region <- gsub(paste0("-", year_short, "0101\\.osm\\.pbf"), "", region)
  return(region)
}

# Years to process
if (!exists("years", inherits = FALSE)) years <- c("16", "21", "26")
if (!exists("versions", inherits = FALSE)) versions <- c("160101", "210101", "260101")

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
