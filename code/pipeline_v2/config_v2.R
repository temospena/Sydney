# config_v2.R
# Centralized configuration for pipeline_v2 (BRouter-based routing)
# ===========================================================================
# ★ USER SETTINGS — edit these to control what the pipeline runs
# ===========================================================================

# Set server = TRUE if running on the high-memory server,
# or server = FALSE if running locally on your laptop.
# This controls the Java heap memory allocation for BRouter.
server <- FALSE

# City to process.
# For local testing, keep to a single city (Lisbon).
# On the server, you can expand this list.
target_cities <- c("Lisbon")
# target_cities <- c("Lisbon", "Chicago")      # next step: also test Chicago
# target_cities <- c("Lisbon", "Chicago", ...)  # full server run

# Number of OD pairs to generate and route.
# Start small (1000 or 10000) to verify results before scaling to 20000.
n_od_pairs <- 20000
# n_od_pairs <- 10000
# n_od_pairs <- 1000

# Years (2-digit) and full version strings — keep these in sync
years <- c("16", "21", "26")
versions <- c("160101", "210101", "260101")

# BRouter ports — must match docker-compose.yml
# docker-compose exposes: 17771 (2016), 17772 (2021), 17773 (2026)
BROUTER_PORTS <- c("16" = "17771", "21" = "17772", "26" = "17773")

# Set TRUE to re-run all steps even if output files already exist
FORCE_RERUN <- TRUE

# H3 resolution for OD grid
h3_res <- 9

# Distance decay parameters (lognormal)
mu_log <- 0.33 # mean (log scale)
sd_log <- 0.66 # sd (log scale)

# Color scheme for CI categories (shared across plots)
ci_colors <- c(
    "strong_ci"    = "#054d05",
    "moderate_ci"  = "#1A7832",
    "weak_ci"      = "#AFD4A0",
    "shared_foot"  = "#ebc0d4"
)

# ===========================================================================
# Internal setup — you should not need to edit below this line
# ===========================================================================

# Allow individual scripts launched via run_all to override target_cities
if (exists("city_to_run") && length(city_to_run) > 0) {
    target_cities <- city_to_run
}

# Java memory allocation (automatically set based on server flag)
if (server) {
    java_mem_gb <- 96 # 96 GB for server
} else {
    java_mem_gb <- 8 # 8 GB for local laptop
}
java_mem <- paste0("-Xmx", java_mem_gb, "G")

cat("[CONFIG] Running in", if (server) "SERVER" else "LOCAL", "mode — Java mem:", java_mem, "\n")


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
if (requireNamespace("here", quietly = TRUE)) {
    proj_root <- here::here()
    if (!grepl("media", proj_root) && grepl("media", getwd())) proj_root <- getwd()
} else {
    proj_root <- "."
}

data_dir <- file.path(proj_root, "data/pipeline")
osm_raw_dir <- file.path(proj_root, "data/osm_pbf")
brouter_dir <- file.path(proj_root, "data/brouter")

cat("[DEBUG] Working Directory:", getwd(), "\n")
cat("[DEBUG] Data Directory   :", data_dir, "\n")
cat("[CONFIG] FORCE_RERUN     :", FORCE_RERUN, "\n")
cat("[CONFIG] n_od_pairs      :", n_od_pairs, "\n")
cat("[CONFIG] target_cities   :", paste(target_cities, collapse = ", "), "\n")
