# 02b_od_data.R
# Generate OD matrices using the HuggingFace GBA.ODbLPolygon & GBA.LoD1 datasets
# Replaces 02_od_data.R after source.coop S3 parquet bucket was discontinued (~March 2026)
#
# Key differences vs 02_od_data.R:
#  - Data source for footprints: HuggingFace GBA.ODbLPolygon (GeoJSON tiles)
#  - Data source for heights: HuggingFace GBA.LoD1 (JSON key-value mapping)
#  - Tiles cached locally in data/gba_tiles_cache/ to avoid re-downloading
#  - duckdb/parquet dependency removed 

library(sf)
library(dplyr)
library(purrr)
library(h3jsr)
library(readr)
sf_use_s2(FALSE)

source("code/pipeline/config.R")
if (exists("city_to_run")) target_cities <- city_to_run

miles_to_meters <- 1609.34

# HuggingFace base URLs
HF_GEOJSON_BASE <- "https://huggingface.co/datasets/zhu-xlab/GBA.ODbLPolygon/resolve/main"
HF_POLYGON_BASE <- "https://huggingface.co/datasets/zhu-xlab/GBA.LoD1/resolve/main/Polygon"
HF_JSON_BASE    <- "https://huggingface.co/datasets/zhu-xlab/GBA.LoD1/resolve/main/LoD1"

# All known continent subfolders
CONTINENT_FOLDERS <- c(
  "southamerica", "northamerica", "europe",
  "africa", "asiaeast", "asiawest", "oceania"
)

# Local tile cache directory
TILE_CACHE_DIR <- file.path(proj_root, "data", "gba_tiles_cache")
dir.create(TILE_CACHE_DIR, showWarnings = FALSE, recursive = TRUE)

# Allow up to 20 minutes per tile download (files can be up to 500 MB)
options(timeout = 1200)

# ===========================================================================
# Helper: Python script to convert big JSON to CSV (memory efficient via Python)
# ===========================================================================
py_script_path <- file.path(TILE_CACHE_DIR, "json_to_csv.py")
if (!file.exists(py_script_path)) {
  writeLines(
    c(
      "import sys, json, csv",
      "import os",
      "infile, outfile = sys.argv[1:3]",
      "if os.path.exists(outfile): sys.exit(0)",
      "try:",
      "    with open(infile, 'r') as f:",
      "        d = json.load(f)",
      "    with open(outfile, 'w', newline='') as f:",
      "        writer = csv.writer(f)",
      "        writer.writerow(['key', 'height'])",
      "        for k, v in d.items():",
      "            writer.writerow([k, v.get('height')])",
      "except Exception as e:",
      "    print(f'Error: {e}')",
      "    sys.exit(1)"
    ),
    py_script_path
  )
}

# ===========================================================================
# Helper: Generate 5×5° tile names from a city bbox
# ===========================================================================
get_tile_names_for_bbox <- function(bbox) {
  lon_min_tile <- floor(bbox["xmin"] / 5) * 5
  lon_max_tile <- floor(bbox["xmax"] / 5) * 5
  lat_min_tile <- floor(bbox["ymin"] / 5) * 5
  lat_max_tile <- floor(bbox["ymax"] / 5) * 5

  tiles <- c()
  for (ln in seq(lon_min_tile, lon_max_tile, by = 5)) {
    for (lt in seq(lat_min_tile, lat_max_tile, by = 5)) {
      tile <- paste0(
        if (ln < 0) "w" else "e", sprintf("%03d", abs(ln)), "_",
        if (lt + 5 < 0) "s" else "n", sprintf("%02d", abs(lt + 5)), "_",
        if (ln + 5 < 0) "w" else "e", sprintf("%03d", abs(ln + 5)), "_",
        if (lt < 0) "s" else "n", sprintf("%02d", abs(lt))
      )
      tiles <- c(tiles, tile)
    }
  }
  unique(tiles)
}

# ===========================================================================
# Helper: Determine likely continent folder(s) for a tile from its coordinates
# ===========================================================================
get_continent_candidates <- function(tile_name) {
  parts <- strsplit(tile_name, "_")[[1]]
  if (length(parts) != 4) return(CONTINENT_FOLDERS)

  parse_coord <- function(s) {
    dir <- tolower(substr(s, 1, 1))
    val <- as.numeric(substr(s, 2, nchar(s)))
    if (dir %in% c("w", "s")) -val else val
  }
  lon1 <- parse_coord(parts[1])
  lat1 <- parse_coord(parts[2])  
  lon2 <- parse_coord(parts[3])
  lat2 <- parse_coord(parts[4])  
  clon <- (lon1 + lon2) / 2
  clat <- (lat1 + lat2) / 2

  if (clon >= -82 && clon <= -34 && clat >= -56 && clat <= 13)
    return("southamerica")
  if (clon >= -170 && clon <= -55 && clat > 5)
    return("northamerica")
  if (clon >= -30 && clon <= 50 && clat >= 33 && clat <= 75)
    return("europe")
  if (clon >= -20 && clon <= 55 && clat >= -38 && clat <= 40)
    return("africa")
  if (clon > 40 && clon <= 80 && clat >= 5)
    return(c("asiawest", "europe"))
  if (clon > 70 && clon <= 150 && clat >= -15 && clat <= 55)
    return(c("asiaeast", "asiawest"))
  if (clon > 100 || clon < -140)
    return(c("oceania", "asiaeast"))

  return(CONTINENT_FOLDERS)
}

# ===========================================================================
# Download a tile (geojson + json) from HuggingFace
# ===========================================================================
download_tile_hf <- function(tile_name) {
  geojson_file  <- file.path(TILE_CACHE_DIR, paste0(tile_name, ".geojson"))
  geojson2_file <- file.path(TILE_CACHE_DIR, paste0(tile_name, "_part2.geojson"))
  json_file     <- file.path(TILE_CACHE_DIR, paste0(tile_name, ".json"))
  csv_file      <- file.path(TILE_CACHE_DIR, paste0(tile_name, ".csv"))

  candidates <- get_continent_candidates(tile_name)
  found_continent <- NULL
  
  # 1. Fetch GeoJSON (Part 1 - ODbL)
  if (!file.exists(geojson_file) || file.size(geojson_file) < 10000) {
    for (continent in candidates) {
      url <- paste0(HF_GEOJSON_BASE, "/", continent, "/", tile_name, ".geojson")
      message(paste("    Trying GeoJSON (Part 1)", continent, "->", tile_name, "..."))
      tmp <- paste0(geojson_file, ".tmp")
      ok <- tryCatch({
        download.file(url, tmp, mode = "wb", quiet = TRUE, method = "libcurl")
        TRUE
      }, error = function(e) FALSE)
      
      if (ok && file.exists(tmp) && file.size(tmp) > 10000) {
        file.rename(tmp, geojson_file)
        found_continent <- continent
        message(paste("    Downloaded GeoJSON (Part 1) from:", continent))
        break
      }
      if (file.exists(tmp)) file.remove(tmp)
    }
  } else {
    message(paste("    [CACHE HIT] GeoJSON (Part 1) for", tile_name))
  }

  # 1.5 Fetch GeoJSON (Part 2 - Google/CLSM)
  if (!file.exists(geojson2_file) || file.size(geojson2_file) < 10000) {
    check_conts <- if (!is.null(found_continent)) c(found_continent, candidates) else candidates
    check_conts <- unique(check_conts)
    for (continent in check_conts) {
      url <- paste0(HF_POLYGON_BASE, "/", continent, "/", tile_name, ".geojson")
      message(paste("    Trying GeoJSON (Part 2)", continent, "->", tile_name, "..."))
      tmp <- paste0(geojson2_file, ".tmp")
      ok <- tryCatch({
        download.file(url, tmp, mode = "wb", quiet = TRUE, method = "libcurl")
        TRUE
      }, error = function(e) FALSE)
      
      if (ok && file.exists(tmp) && file.size(tmp) > 10000) {
        file.rename(tmp, geojson2_file)
        message(paste("    Downloaded GeoJSON (Part 2) from:", continent))
        break
      }
      if (file.exists(tmp)) file.remove(tmp)
    }
  } else {
    message(paste("    [CACHE HIT] GeoJSON (Part 2) for", tile_name))
  }

  if (!file.exists(geojson_file) && !file.exists(geojson2_file)) {
    message(paste("    [NOT FOUND] Tile completely unavailable:", tile_name))
    return(NULL)
  }

  # 2. Fetch JSON (Heights)
  if (!file.exists(json_file) || file.size(json_file) < 1000) {
    # If we know the continent from GeoJSON hit, prioritize it
    check_conts <- if (!is.null(found_continent)) c(found_continent, candidates) else candidates
    check_conts <- unique(check_conts)
    
    for (continent in check_conts) {
      url <- paste0(HF_JSON_BASE, "/", continent, "/", tile_name, ".json")
      message(paste("    Trying JSON", continent, "->", tile_name, "..."))
      tmp <- paste0(json_file, ".tmp")
      ok <- tryCatch({
        download.file(url, tmp, mode = "wb", quiet = TRUE, method = "libcurl")
        TRUE
      }, error = function(e) FALSE)
      
      if (ok && file.exists(tmp) && file.size(tmp) > 1000) {
        file.rename(tmp, json_file)
        message(paste("    Downloaded JSON from:", continent))
        break
      }
      if (file.exists(tmp)) file.remove(tmp)
    }
  } else {
    message(paste("    [CACHE HIT] JSON for", tile_name))
  }

  # 3. Convert JSON to CSV using python (fast, memory safe) 
  if (file.exists(json_file) && !file.exists(csv_file)) {
    message("    Converting JSON heights to CSV...")
    system2("python3", args = c(py_script_path, json_file, csv_file))
  }

  return(list(geojson = geojson_file, geojson2 = geojson2_file, csv = csv_file))
}

# ===========================================================================
# Fetch building centroids with heights and merge
# ===========================================================================
fetch_building_points_hf <- function(city_name, city_poly, tile_names) {
  all_parts <- list()

  for (tile_name in tile_names) {
    files <- download_tile_hf(tile_name)
    if (is.null(files)) next

    message(paste("    Reading tile files for", tile_name, "..."))
    buildings_raw1 <- tryCatch(
      if (file.exists(files$geojson)) st_read(files$geojson, quiet = TRUE) else NULL,
      error = function(e) NULL
    )
    buildings_raw2 <- tryCatch(
      if (file.exists(files$geojson2)) st_read(files$geojson2, quiet = TRUE) else NULL,
      error = function(e) NULL
    )
    
    parts <- list()
    if (!is.null(buildings_raw1) && nrow(buildings_raw1) > 0) parts[[1]] <- buildings_raw1
    if (!is.null(buildings_raw2) && nrow(buildings_raw2) > 0) parts[[2]] <- buildings_raw2
    
    if (length(parts) == 0) next
    buildings_raw <- dplyr::bind_rows(parts) |> st_as_sf()

    # Fix EPSG:3857 (declared as CRS84)
    buildings_3857 <- st_set_crs(buildings_raw, 3857)

    # Calculate footprint in square meters
    buildings_3857 <- buildings_3857 |>
      mutate(footprint_m2 = round(as.numeric(st_area(geometry)))) |>
      filter(footprint_m2 > 0)

    # Transform to WGS84
    buildings_wgs84 <- st_transform(buildings_3857, 4326)

    # Clip to city bounds
    in_city <- st_intersects(buildings_wgs84, city_poly, sparse = FALSE)[, 1]
    buildings_city <- buildings_wgs84[in_city, ]
    
    if (nrow(buildings_city) == 0) next

    # Construct the unique key to join with heights
    buildings_city <- buildings_city |>
      mutate(key = paste0(source, id, region))

    # Read the heights CSV if it exists
    if (file.exists(files$csv)) {
      message("    Merging heights...")
      heights_df <- read_csv(files$csv, show_col_types = FALSE)
      buildings_city <- buildings_city |>
        left_join(heights_df, by = "key") |>
        mutate(
          height_m  = coalesce(height, 3), # default to 1 floor (3m) if missing
          est_floors= pmax(1, round(height_m / 3)),
          volume_m3 = round(footprint_m2 * height_m)
        )
    } else {
      # Fallback to 1 floor if height map is completely missing
      buildings_city <- buildings_city |>
        mutate(
          height_m  = 3, 
          est_floors= 1,
          volume_m3 = footprint_m2 * 3
        )
    }

    # Extract centroids to sf
    centroids <- buildings_city |>
      st_centroid() |>
      select(id, footprint_m2, height_m, est_floors, volume_m3)

    all_parts[[tile_name]] <- centroids
  }

  if (length(all_parts) == 0) return(NULL)
  do.call(rbind, all_parts)
}

# ===========================================================================
# Main loop
# ===========================================================================
set.seed(42)

for (city in target_cities) {
  city_lower     <- tolower(city)
  city_dir       <- file.path(data_dir, city_lower)
  city_poly_path <- file.path(city_dir, paste0(city_lower, "_10km.gpkg"))

  if (!file.exists(city_poly_path)) {
    warning(paste("Missing poly for", city))
    next
  }

  origins_path      <- file.path(city_dir, "origins.gpkg")
  destinations_path <- file.path(city_dir, "destinations.gpkg")

  if (file.exists(origins_path) && file.exists(destinations_path) && !FORCE_RERUN) {
    o_check <- st_read(origins_path, quiet = TRUE)
    if (nrow(o_check) == n_od_pairs) {
      cat(paste("OD matrices for", city, "already exist. Skipping...\n"))
      next
    }
  }

  city_poly <- st_read(city_poly_path, quiet = TRUE)
  bbox      <- st_bbox(city_poly)

  tile_names <- get_tile_names_for_bbox(bbox)
  tile_names <- tile_names[!is.na(tile_names) & tile_names != ""]

  if (length(tile_names) == 0) {
    warning(paste("Could not determine tile names for", city))
    next
  }

  cat(paste0("Fetching buildings for ", city, " (tiles: ", paste(tile_names, collapse = ", "), ")...\n"))
  buildings <- fetch_building_points_hf(city, city_poly, tile_names)

  if (is.null(buildings) || nrow(buildings) == 0) {
    warning(paste("No buildings fetched for", city))
    next
  }
  cat(paste0("  => ", nrow(buildings), " buildings found with height/volume estimates.\n"))

  # --------------------------------------------------------------------------
  # H3 grid aggregation
  # --------------------------------------------------------------------------
  cat("Processing buildings to H3 grid...\n")

  buildings <- buildings |>
    mutate(h3_addr = point_to_cell(geometry, res = h3_res)) |>
    filter(volume_m3 > 0)

  valid_h3_pool <- unique(buildings$h3_addr)

  # Full land use grid
  cat("Generating full land use dataset for accessibility...\n")
  land_use_h3 <- buildings |>
    st_drop_geometry() |>
    group_by(h3_addr) |>
    summarise(volume = sum(volume_m3, na.rm = TRUE), .groups = "drop") |>
    filter(volume > 0)

  land_use_sf <- h3jsr::cell_to_polygon(land_use_h3$h3_addr, simple = FALSE) |>
    mutate(id = land_use_h3$h3_addr, volume = land_use_h3$volume) |>
    select(id, volume, geometry)

  st_write(land_use_sf, file.path(city_dir, "land_use.gpkg"), delete_dsn = TRUE, quiet = TRUE)

  # --------------------------------------------------------------------------
  # OD sampling
  # --------------------------------------------------------------------------
  cat("Sampling destinations and generating origin targets...\n")

  dest_samples <- buildings |>
    slice_sample(n = n_od_pairs, weight_by = volume_m3, replace = TRUE) |>
    st_drop_geometry() |>
    mutate(
      trip_id       = row_number(),
      target_dist_m = rlnorm(n(), meanlog = mu_log, sdlog = sd_log) * miles_to_meters
    )

  avg_spacing <- 400

  find_origin <- function(dest_h3, target_m, pool) {
    ring_radius     <- ceiling(target_m / avg_spacing)
    potential_cells <- get_ring(dest_h3, ring_radius) |> unlist()
    candidates      <- pool[pool %in% potential_cells]
    if (length(candidates) == 0) return(sample(pool, 1))
    sample(candidates, 1)
  }

  origins_h3           <- map2_chr(dest_samples$h3_addr, dest_samples$target_dist_m,
                                   ~ find_origin(.x, .y, valid_h3_pool))
  dest_samples$orig_h3 <- origins_h3

  cat("Generating SF centroids and saving...\n")

  dest_sf <- h3jsr::cell_to_polygon(dest_samples$h3_addr, simple = FALSE) |>
    st_centroid() |>
    mutate(
      id      = dest_samples$trip_id,
      trip_id = dest_samples$trip_id,
      type    = "destination",
      volume  = dest_samples$volume_m3
    )

  orig_sf <- h3jsr::cell_to_polygon(dest_samples$orig_h3, simple = FALSE) |>
    st_centroid() |>
    mutate(
      id      = dest_samples$trip_id,
      trip_id = dest_samples$trip_id,
      type    = "origin",
      volume  = 1L
    )

  st_write(orig_sf, origins_path,      append = FALSE, delete_dsn = TRUE, quiet = TRUE)
  st_write(dest_sf, destinations_path, append = FALSE, delete_dsn = TRUE, quiet = TRUE)

  cat(paste0("Successfully generated OD matrices for ", city, "\n"))
}
