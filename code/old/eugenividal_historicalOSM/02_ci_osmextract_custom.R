# ================================================================
# R/02_ci_osmextract_custom.R
# Build the processed OSM cycling infrastructure layer per snapshot
# (osmextract custom: explicit tag-based selection + optional NDC flagging).
#
# Outputs (TWO FILES):
#   1) data/<city_tag>/<city_tag>_ci_osmextract_custom_total_<version>.gpkg
#        TOTAL incl. NDC flags (for mapping + QA)
#   2) data/<city_tag>/<city_tag>_ci_osmextract_custom_excl_ndc_<version>.gpkg
#        EXCL_NDC (NDC-flagged segments excluded; for length calculations)
#
# Requires (from R/00_setup.R):
#   city_tag, infra_region, crs_work, VERSIONS, FORCE_BUILD, DEDUPE_TOL_M
# ================================================================

# -----------------------------
# Settings (you can tweak)
# -----------------------------
ENABLE_NDC <- TRUE
DEDUPE_TOL_M = 15 # meters

# One-pass NDC settings (FLAGGING ONLY)
NDC_PROP_IN_BUF  <- 0.5
NDC_MIN_IN_BUF_M <- 20

# NDC logic (4-category scheme):
# - Reference: strong CI
# - Pass 1 targets: moderate CI (painted lanes)
NDC_REF_CAT      <- "strong_ci"
NDC_PASS1_TARGET <- "moderate_ci"

# -----------------------------
# Tag value lists
# -----------------------------
# Stronger on-road provision (often, but not always, physically separated)
STRONG_ONROAD_VALS <- c("track", "opposite_track")

# Moderate on-road provision (painted lanes)
MODERATE_ONROAD_VALS <- c("lane", "opposite_lane")

# Weak on-road provision (shared with motor vehicles)
WEAK_ONROAD_VALS <- c("share_busway", "shared_lane")

# Shared foot/path class (access-based)
FOOT_SHARED_HWY  <- c("path", "footway", "pedestrian")
FOOT_SHARED_BIC  <- c("yes", "designated")
FOOT_SHARED_FOOT <- c("yes", "designated")

# Pavement cycle-lane cases (older BCN-style tagging)
# We INCLUDE these in shared_foot, but we do NOT create any subclass column.
PAVEMENT_LANE_HWY <- c("footway", "path", "pedestrian")
PAVEMENT_LANE_BIC <- c("designated")  # strict on purpose
PAVEMENT_LANE_ALLOW_SEGREGATED_YES <- TRUE

# -----------------------------
# Helpers
# -----------------------------
read_perim_ll <- function(city_tag) {
  p <- file.path("data", city_tag, paste0(city_tag, "_perimeter.gpkg"))
  if (!file.exists(p)) stop("Perimeter file not found: ", p)
  sf::st_read(p, quiet = TRUE) |>
    sf::st_make_valid() |>
    sf::st_transform(4326)
}

cycleway_cols <- function(x) {
  names(x)[grepl("^cycleway($|[:_])", names(x), ignore.case = TRUE)]
}

has_cycleway_vals <- function(x, vals) {
  cols <- cycleway_cols(x)
  if (!length(cols)) return(rep(FALSE, nrow(x)))
  
  vals <- tolower(vals)
  out  <- rep(FALSE, nrow(x))
  
  for (cc in cols) {
    v <- tolower(trimws(as.character(x[[cc]])))
    v[is.na(v)] <- ""
    hit <- vapply(
      strsplit(v, ";", fixed = TRUE),
      function(parts) any(trimws(parts) %in% vals),
      logical(1)
    )
    out <- out | hit
  }
  out
}

normalize_lines <- function(x) {
  if (!inherits(x, "sf") || !nrow(x)) return(x[0, ])
  
  x <- sf::st_make_valid(x)
  x <- x[!sf::st_is_empty(x), , drop = FALSE]
  if (!nrow(x)) return(x[0, ])
  
  gt <- sf::st_geometry_type(x)
  x <- x[gt %in% c("LINESTRING", "MULTILINESTRING"), , drop = FALSE]
  if (!nrow(x)) return(x[0, ])
  
  x <- suppressWarnings(sf::st_cast(x, "LINESTRING"))
  x <- x[!sf::st_is_empty(x), , drop = FALSE]
  sf::st_make_valid(x)
}

# -----------------------------
# NDC helper: one pass (FLAGGING ONLY)
# -----------------------------
ndc_pass_flag <- function(core_ll,
                          ref_cat = "strong_ci",
                          target_cat = "moderate_ci",
                          tol_m = 15,
                          prop_in_buf = 0.5,
                          min_in_buf_m = 20,
                          crs_metric = get("crs_work", envir = .GlobalEnv),
                          pass_label = "p1") {
  
  stopifnot(inherits(core_ll, "sf"), "cycle_cat" %in% names(core_ll))
  
  if (!"ndc_keep" %in% names(core_ll)) core_ll$ndc_keep <- TRUE
  if (!"ndc_pass" %in% names(core_ll)) core_ll$ndc_pass <- NA_character_
  if (!"ndc_ref_cat" %in% names(core_ll)) core_ll$ndc_ref_cat <- NA_character_
  if (!"ndc_target_cat" %in% names(core_ll)) core_ll$ndc_target_cat <- NA_character_
  
  ref <- core_ll[core_ll$cycle_cat == ref_cat, , drop = FALSE]
  trg <- core_ll[core_ll$cycle_cat == target_cat & core_ll$ndc_keep, , drop = FALSE]
  if (!nrow(ref) || !nrow(trg)) return(core_ll)
  
  ref_m <- sf::st_transform(ref, crs_metric)
  trg_m <- sf::st_transform(trg, crs_metric)
  
  buf <- sf::st_buffer(sf::st_union(sf::st_geometry(ref_m)), tol_m)
  
  trg_m$.rid <- seq_len(nrow(trg_m))
  L <- as.numeric(sf::st_length(sf::st_geometry(trg_m)))
  
  inside <- suppressWarnings(sf::st_intersection(trg_m, buf))
  Lin <- rep(0, nrow(trg_m))
  if (nrow(inside)) {
    Lin_sum <- tapply(as.numeric(sf::st_length(sf::st_geometry(inside))), inside$.rid, sum)
    Lin[as.integer(names(Lin_sum))] <- as.numeric(Lin_sum)
  }
  
  share <- Lin / pmax(L, 1e-6)
  flag  <- (Lin >= min_in_buf_m) & (share >= prop_in_buf)
  
  if (any(flag)) {
    trg_idx_in_core <- which(core_ll$cycle_cat == target_cat & core_ll$ndc_keep)
    flag_idx <- trg_idx_in_core[flag]
    
    core_ll$ndc_keep[flag_idx]       <- FALSE
    core_ll$ndc_pass[flag_idx]       <- pass_label
    core_ll$ndc_ref_cat[flag_idx]    <- ref_cat
    core_ll$ndc_target_cat[flag_idx] <- target_cat
  }
  
  core_ll
}

# -----------------------------
# Main builder (per version)
# -----------------------------
build_core_ndc <- function(version, force_build = FALSE, tol_m = 15) {
  stopifnot(exists("city_tag"), exists("infra_region"), exists("crs_work"))
  
  city_dir <- file.path("data", city_tag)
  dir.create(city_dir, showWarnings = FALSE, recursive = TRUE)
  
  out_excl_ndc <- file.path(
    city_dir,
    paste0(city_tag, "_ci_osmextract_custom_excl_ndc_", version, ".gpkg")
  )
  out_total <- file.path(
    city_dir,
    paste0(city_tag, "_ci_osmextract_custom_total_", version, ".gpkg")
  )
  
  if (isTRUE(force_build)) {
    if (file.exists(out_excl_ndc)) file.remove(out_excl_ndc)
    if (file.exists(out_total))    file.remove(out_total)
  } else {
    if (file.exists(out_excl_ndc) && file.exists(out_total)) {
      message("Skip: ", basename(out_excl_ndc), " + ", basename(out_total))
      return(out_excl_ndc)
    }
  }
  
  # -----------------------------------------------------
  # Download + clip
  # -----------------------------------------------------
  perim_ll <- read_perim_ll(city_tag)
  
  message("Download/build: ", infra_region, " @ ", version)
  lines <- osmextract::oe_get(
    place                 = infra_region,
    boundary              = sf::st_bbox(perim_ll),
    boundary_type         = "clipsrc",
    layer                 = "lines",
    version               = version,
    extra_tags = c(extra_tags = c(
      "highway",
      "cycleway", "cycleway:left", "cycleway:right", "cycleway:both",
      "bicycle", "foot", "segregated"
    )),
    force_vectortranslate = TRUE,
    quiet                 = FALSE
  )
  
  perim_m <- sf::st_transform(perim_ll, crs_work)
  lines_m <- sf::st_transform(lines, crs_work)
  lines_m <- sf::st_intersection(
    sf::st_make_valid(lines_m),
    sf::st_make_valid(perim_m)
  )
  
  if (!nrow(lines_m)) stop("0 features after clipping for version ", version)
  
  lines_m <- normalize_lines(lines_m)
  if (!nrow(lines_m)) stop("0 line features after normalisation for version ", version)
  
  # -----------------------------------------------------
  # Core selection + labelling (4-category scheme only)
  # -----------------------------------------------------
  highway    <- tolower(trimws(as.character(lines_m$highway)))
  bicycle    <- tolower(trimws(as.character(lines_m$bicycle)))
  foot       <- tolower(trimws(as.character(lines_m$foot)))
  segregated <- tolower(trimws(as.character(lines_m$segregated)))
  
  is_cyclewy <- !is.na(highway) & highway == "cycleway"
  
  has_strong_onroad   <- has_cycleway_vals(lines_m, STRONG_ONROAD_VALS)
  has_moderate_onroad <- has_cycleway_vals(lines_m, MODERATE_ONROAD_VALS)
  has_weak_onroad     <- has_cycleway_vals(lines_m, WEAK_ONROAD_VALS)
  
  # Standard shared foot/path class (shared-use, not explicitly segregated)
  is_foot_shared <- (!is.na(highway) & highway %in% FOOT_SHARED_HWY) &
    (!is.na(bicycle) & bicycle %in% FOOT_SHARED_BIC) &
    (!is.na(foot) & foot %in% FOOT_SHARED_FOOT) &
    !(segregated %in% "yes")
  
  # Pavement-lane inclusion (older BCN): bicycle=designated on footway/path/pedestrian.
  # We include these as shared_foot even if segregated=yes, because they represent
  # cycle lanes routed over pedestrian infrastructure.
  is_pavement_lane <- (!is.na(highway) & highway %in% PAVEMENT_LANE_HWY) &
    (!is.na(bicycle) & bicycle %in% PAVEMENT_LANE_BIC) &
    (isTRUE(PAVEMENT_LANE_ALLOW_SEGREGATED_YES) | !(segregated %in% "yes"))
  
  lines_m$cycle_cat <- NA_character_
  
  # 1) dedicated cycleways
  lines_m$cycle_cat[is_cyclewy] <- "strong_ci"
  
  # 2) pedestrian-infrastructure cycling (standard shared foot OR pavement-lane cases)
  sel_foot <- (is_foot_shared | is_pavement_lane) & is.na(lines_m$cycle_cat)
  lines_m$cycle_cat[sel_foot] <- "shared_foot"
  
  # 3) on-road cycleway tagging
  sel_other <- is.na(lines_m$cycle_cat)
  lines_m$cycle_cat[sel_other & has_strong_onroad] <- "strong_ci"
  
  sel_other <- is.na(lines_m$cycle_cat)
  lines_m$cycle_cat[sel_other & has_moderate_onroad] <- "moderate_ci"
  
  sel_other <- is.na(lines_m$cycle_cat)
  lines_m$cycle_cat[sel_other & has_weak_onroad] <- "weak_ci"
  
  core <- lines_m[!is.na(lines_m$cycle_cat), , drop = FALSE]
  if (!nrow(core)) stop("0 features after CUSTOM filter/labelling for version ", version)
  
  # -----------------------------------------------------
  # NDC pass (FLAGGING ONLY)
  # -----------------------------------------------------
  core_ll <- sf::st_transform(core, 4326)
  
  if (isTRUE(ENABLE_NDC)) {
    core_ll$ndc_keep       <- TRUE
    core_ll$ndc_pass       <- NA_character_
    core_ll$ndc_ref_cat    <- NA_character_
    core_ll$ndc_target_cat <- NA_character_
    
    core_ll <- ndc_pass_flag(
      core_ll,
      ref_cat      = NDC_REF_CAT,
      target_cat   = NDC_PASS1_TARGET,
      tol_m        = tol_m,
      prop_in_buf  = NDC_PROP_IN_BUF,
      min_in_buf_m = NDC_MIN_IN_BUF_M,
      crs_metric   = crs_work,
      pass_label   = "p1"
    )
  } else {
    if (!"ndc_keep" %in% names(core_ll)) core_ll$ndc_keep <- NA
    if (!"ndc_pass" %in% names(core_ll)) core_ll$ndc_pass <- NA_character_
    if (!"ndc_ref_cat" %in% names(core_ll)) core_ll$ndc_ref_cat <- NA_character_
    if (!"ndc_target_cat" %in% names(core_ll)) core_ll$ndc_target_cat <- NA_character_
  }
  
  # -----------------------------------------------------
  # Write outputs
  # -----------------------------------------------------
  excl_ndc <- core_ll[is.na(core_ll$ndc_keep) | core_ll$ndc_keep, , drop = FALSE]
  
  sf::st_write(core_ll,  out_total,    driver = "GPKG", append = FALSE, quiet = TRUE)
  sf::st_write(excl_ndc, out_excl_ndc, driver = "GPKG", append = FALSE, quiet = TRUE)
  
  message("Wrote TOTAL:    ", basename(out_total),    " (n=", nrow(core_ll), ")")
  message("Wrote EXCL_NDC: ", basename(out_excl_ndc), " (n=", nrow(excl_ndc), ")")
  
  if (isTRUE(ENABLE_NDC)) {
    message("NDC summary (TOTAL set):")
    print(table(core_ll$cycle_cat, core_ll$ndc_keep, useNA = "ifany"))
    message("Flagged by pass:")
    print(table(core_ll$ndc_pass, useNA = "ifany"))
  }
  
  out_excl_ndc
}


## RUN ##
for (v in VERSIONS) {
  build_core_ndc(version = v, force_build = FORCE_BUILD, tol_m = DEDUPE_TOL_M)
}
