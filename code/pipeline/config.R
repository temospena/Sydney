# config.R
# Centralized configuration for the CI pipeline
# ===========================================================================
# ★ USER SETTINGS — edit these to control what the pipeline runs
# ===========================================================================

# Cities to process. Comment out the full list and uncomment a single name
# to test / re-run just one city.
# target_cities <- c(
                  # "Amsterdam", "Austin", "Barcelona"
                  # "Beijing", "Berlin", "Bogota",
                  # "Bologna", "Brussels", "Buenos Aires",
                  #  "Chicago", "Christchurch", "Curitiba", "Dublin", "Gent", "Glasgow",
                  #  "Graz", "Hamburg", "Helsinki", "Kyoto", "Leeds",
                  # "Ljubljana", "London", "Lyon", "Madrid", "Melbourne" # "Lisbon",
                  # "Mexico City", "Milan", "Minneapolis", "Montpellier", "Montréal",
                  # "Munich", "Nantes", "New York", "Oslo", "Paris", "Portland",
                  # "San Francisco", "Santiago", "Sao Paulo", "Seattle", "Seoul",
                  # "Seville", "Shanghai", "Stockholm", "Strasbourg", "Sydney", "Taipei",
                  # "Tokyo", "Turin", "Vancouver", "Vienna", "Warsaw", "Zurich"
                  # ) #cairo, cape town,  hong kong (> 100km in 2026)
# target_cities <- c("Sydney", "Paris", "New York", "Lisbon")
target_cities <- "Lisbon"

# Years (2-digit) and full version strings — keep these in sync
years <- c("16", "19", "21", "24", "26")
versions <- c("160101", "190101", "210101", "240101", "260101")

# Set TRUE to re-run the routing step (and delete existing trips_*.rds) without rebuilding networks
REROUTE_ONLY <- TRUE

# Set TRUE to re-run all steps even if output files already exist, including donwload osm files
FORCE_RERUN <- FALSE

# Routing settings
n_od_pairs <- 20000
java_mem <- "-Xmx96G"
lts_levels <- c(1, 2, 3, 4) # Select which LTS thresholds to route (1 to 4)  ## NOT RUN 3, 4 FOR NOW

# Routing: Should we override default LTS and force LTS=1 for all Cycling Infrastructure segments?
lts1_for_ci <- TRUE

# H3 resolution and lognormal distance decay for OD sampling (v2 approach)
h3_res <- 9
mu_log <- 0.33 # mean (log scale) for lognormal trip distance decay
sd_log <- 0.66 # sd (log scale) for lognormal trip distance decay

# Color scheme for CI categories (shared across plots and maps)
ci_colors <- c(
  "Separated cycling infrastructure"                = "#054d05",
  "Painted on-road cycle lane"                      = "#1A7832",
  "Mixed traffic (motor vehicles with light infra)" = "#AFD4A0",
  "Cycling on pedestrian infrastructure"            = "#ebc0d4"
)

# ===========================================================================
# Internal setup — you should not need to edit below this line
# ===========================================================================

# Allow individual scripts launched via run_city.R / 00_run_all.R to override
# target_cities with a single city passed in city_to_run
if (exists("city_to_run") && length(city_to_run) > 0) {
  target_cities <- city_to_run
}

cat("[CONFIG] FORCE_RERUN is currently:", FORCE_RERUN, "\n")

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
if (requireNamespace("here", quietly = TRUE)) {
  proj_root <- here::here()
  # If running from the media drive, use cwd as the root
  if (!grepl("media", proj_root) && grepl("media", getwd())) proj_root <- getwd()
  data_dir <- file.path(proj_root, "data/pipeline")
  osm_raw_dir <- file.path(proj_root, "data/osm_pbf")
} else {
  proj_root <- "."
  data_dir <- "data/pipeline"
  osm_raw_dir <- "data/osm_pbf"
}
cat("[DEBUG] Working Directory:", getwd(), "\n")
cat("[DEBUG] Data Directory:", data_dir, "\n")

# ---------------------------------------------------------------------------
# Geofabrik region lookup table
# ---------------------------------------------------------------------------
# data/geofabrik_regions.csv  columns: city, year (2-digit), geofabrik_region
# The region is the URL path segment, e.g. "north-america/us/illinois"
# To add a new city: append 3 rows (one per year) to that CSV file.

.geofabrik_csv_path <- file.path(proj_root, "data/geofabrik_regions.csv")

if (file.exists(.geofabrik_csv_path)) {
  .geofabrik_table <- read.csv(.geofabrik_csv_path, stringsAsFactors = FALSE)
  .geofabrik_table$year <- as.character(.geofabrik_table$year)
  cat("[CONFIG] Loaded geofabrik_regions.csv with", nrow(.geofabrik_table), "rows.\n")
} else {
  warning("[CONFIG] data/geofabrik_regions.csv not found - falling back to hardcoded mapping.")
  .geofabrik_table <- NULL
}

# Look up the Geofabrik region path (e.g. "north-america/us/illinois")
# year_short: 2-character string "16", "21", or "26"
get_geofabrik_region <- function(city, year_short) {
  year_short <- as.character(year_short)
  city_norm <- trimws(city)

  # --- CSV lookup (preferred) ---
  if (!is.null(.geofabrik_table)) {
    row <- .geofabrik_table[
      tolower(.geofabrik_table$city) == tolower(city_norm) &
        .geofabrik_table$year == year_short,
    ]
    if (nrow(row) == 1L) {
      return(row$geofabrik_region)
    }
    if (nrow(row) > 1L) {
      warning(paste("Multiple rows in geofabrik_regions.csv for", city_norm, year_short, "- using first."))
      return(row$geofabrik_region[1])
    }
    message(paste("[CONFIG] No CSV entry for", city_norm, year_short, "- using hardcoded fallback."))
  }

  # --- Hardcoded fallback (legacy, for cities not yet in the CSV) ---
  city_lower <- tolower(city_norm)
  if (city_lower == "barcelona") {
    prefix <- if (as.numeric(year_short) >= 22) "europe/spain/cataluna" else "europe/spain"
  } else if (city_lower == "seville") {
    prefix <- if (as.numeric(year_short) >= 21) "europe/spain/andalucia" else "europe/spain"
  } else if (city_lower == "madrid") {
    prefix <- if (as.numeric(year_short) >= 22) "europe/spain/madrid" else "europe/spain"
  } else if (city_lower == "tokyo") {
    prefix <- if (year_short == "16") "asia/japan" else "asia/japan/kanto"
  } else if (city_lower == "kyoto") {
    prefix <- if (year_short == "16") "asia/japan" else "asia/japan/kansai"
  } else if (city_lower == "shanghai") {
    prefix <- if (year_short == "26") "asia/china/shanghai" else "asia/china"
  } else if (city_lower == "sao paulo") {
    prefix <- if (year_short == "16") "south-america/brazil" else "south-america/brazil/sudeste"
  } else if (city_lower == "curitiba") {
    prefix <- if (year_short == "16") "south-america/brazil" else "south-america/brazil/sul"
  } else {
    mapping <- list(
      "sydney"       = "australia-oceania/australia",
      "lisbon"       = "europe/portugal",
      "paris"        = "europe/france/ile-de-france",
      "munich"       = "europe/germany/bayern/oberbayern",
      "london"       = "europe/united-kingdom/england/greater-london",
      "new york"     = "north-america/us/new-york",
      "portland"     = "north-america/us/oregon",
      "santiago"     = "south-america/chile",
      "brussels"     = "europe/belgium",
      "vancouver"    = "north-america/canada/british-columbia",
      "milan"        = "europe/italy/nord-ovest",
      "mexico city"  = "north-america/mexico",
      "bogota"       = "south-america/colombia",
      "montréal"     = "north-america/canada/quebec",
      "minneapolis"  = "north-america/us/minnesota",
      "berlin"       = "europe/germany/berlin",
      "christchurch" = "australia-oceania/new-zealand",
      "lyon"         = "europe/france/rhone-alpes",
      "seoul"        = "asia/south-korea",
      "cairo"        = "africa/egypt",
      "bologna"      = "europe/italy/nord-est",
      "cape town"    = "africa/south-africa-and-lesotho",
      "melbourne"    = "australia-oceania/australia",
      "vienna"       = "europe/austria",
      "oslo"         = "europe/norway",
      "dublin"       = "europe/ireland-and-northern-ireland",
      "taipei"       = "asia/taiwan",
      "turin"        = "europe/italy/nord-ovest",
      "montpellier"  = "europe/france/languedoc-roussillon",
      "stockholm"    = "europe/sweden",
      "buenos aires" = "south-america/argentina",
      "ljubljana"    = "europe/slovenia",
      "leeds"        = "europe/united-kingdom/england/west-yorkshire",
      "zurich"       = "europe/switzerland",
      "warsaw"       = "europe/poland",
      "chicago"      = "north-america/us/illinois",
      "austin"       = "north-america/us/texas",
      "strasbourg"   = "europe/france/alsace",
      "seattle"      = "north-america/us/washington"
    )
    if (!city_lower %in% names(mapping)) {
      stop(paste("No region mapping found for", city, "- add it to data/geofabrik_regions.csv"))
    }
    prefix <- mapping[[city_lower]]
  }
  return(prefix)
}

# Build the full Geofabrik download URL for a city/year
get_geofabrik_url <- function(city, year_short) {
  region <- get_geofabrik_region(city, year_short)
  paste0("http://download.geofabrik.de/", region, "-", year_short, "0101.osm.pbf")
}

# Derive the filename stem from the region (last path component after "/")
# e.g. "north-america/us/illinois" → "illinois"
get_geofabrik_stem <- function(city, year_short) {
  gsub(".*/", "", get_geofabrik_region(city, year_short))
}
