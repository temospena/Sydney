# config.R
# Centralized configuration for the CI pipeline

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

if (!exists("target_cities") || length(target_cities) == 0) {
  # 24 newly selected cities + original 21 = 45 cities total
  target_cities <- c(
    "Sydney", "Lisbon", "Paris", "Barcelona", "Munich", "London", "New York", "Sao Paulo", "Portland", "Santiago",
    "Brussels", "Vancouver", "Tokyo", "Milan", "Mexico City", "Bogota", "Montréal", "Minneapolis", "Berlin",
    "Seville", "Christchurch",
    "Lyon", "Seoul", "Cairo", "Shanghai", "Bologna", "Cape Town", "Madrid", "Melbourne", "Vienna",
    "Oslo", "Dublin", "Taipei", "Turin", "Montpellier", "Stockholm", "Buenos Aires", "Ljubljana",
    "Leeds", "Zurich", "Warsaw", "Chicago", "Austin", "Strasbourg", "Kyoto"
  )
}

# Helper function to get exact Geofabrik URLs as specified by the user
get_geofabrik_url <- function(city, year_short) {
  base_url <- "http://download.geofabrik.de/"
  postfix <- paste0("-", year_short, "0101.osm.pbf")
  city_lower <- tolower(city)

  # Complex mappings first
  if (city_lower == "barcelona") {
    prefix <- if (as.numeric(year_short) >= 22) "europe/spain/cataluna" else "europe/spain"
  } else if (city_lower == "seville") {
    prefix <- if (as.numeric(year_short) >= 21) "europe/spain/andalucia" else "europe/spain"
  } else if (city_lower == "madrid") {
    prefix <- if (as.numeric(year_short) >= 22) "europe/spain/madrid" else "europe/spain"
  } else if (city_lower == "tokyo") {
    prefix <- if (year_short == "16") "asia/japan" else "asia/japan/kanto"
  } else if (city_lower == "sao paulo") {
    prefix <- if (year_short == "16") "south-america/brazil" else "south-america/brazil/sudeste"
  } else {
    # Simple mapping dictionary
    mapping <- list(
      "sydney" = "australia-oceania/australia",
      "lisbon" = "europe/portugal",
      "paris" = "europe/france/ile-de-france",
      "munich" = "europe/germany/bayern/oberbayern",
      "london" = "europe/united-kingdom/england/greater-london",
      "new york" = "north-america/us/new-york",
      "portland" = "north-america/us/oregon",
      "santiago" = "south-america/chile",
      "brussels" = "europe/belgium",
      "vancouver" = "north-america/canada/british-columbia",
      "milan" = "europe/italy/nord-ovest",
      "mexico city" = "north-america/mexico",
      "bogota" = "south-america/colombia",
      "montréal" = "north-america/canada/quebec",
      "minneapolis" = "north-america/us/minnesota",
      "berlin" = "europe/germany/berlin",
      "christchurch" = "australia-oceania/new-zealand",

      # New mapping
      "lyon" = "europe/france/rhone-alpes",
      "seoul" = "asia/south-korea",
      "cairo" = "africa/egypt",
      "shanghai" = "asia/china",
      "bologna" = "europe/italy/nord-est",
      "cape town" = "africa/south-africa-and-lesotho",
      "melbourne" = "australia-oceania/australia",
      "vienna" = "europe/austria",
      "oslo" = "europe/norway",
      "dublin" = "europe/ireland-and-northern-ireland",
      "taipei" = "asia/taiwan",
      "turin" = "europe/italy/nord-ovest",
      "montpellier" = "europe/france/languedoc-roussillon",
      "stockholm" = "europe/sweden",
      "buenos aires" = "south-america/argentina",
      "ljubljana" = "europe/slovenia",
      "leeds" = "europe/united-kingdom/england/west-yorkshire",
      "zurich" = "europe/switzerland",
      "warsaw" = "europe/poland",
      "chicago" = "north-america/us/illinois",
      "austin" = "north-america/us/texas",
      "strasbourg" = "europe/france/alsace",
      "kyoto" = "asia/japan/kansai"
    )
    if (!city_lower %in% names(mapping)) stop(paste("No URL mapping found for", city))
    prefix <- mapping[[city_lower]]
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
