# ================================================================
# R/04_city_maps.R
# Two-year Leaflet map for osmextract custom + osmactive (native classes)
# Self-contained: defines every helper it calls.
#
# Update:
# - Map uses the four main classes in cycle_cat (no extra subtype overlays).
#
# NDC support (TWO-FILE flagging design, from R/02_ci_osmextract_custom.R):
# - Base network shown in maps (EXCL_NDC, ie excluding flagged duplicates):
#     data/<city_tag>/<city_tag>_ci_osmextract_custom_excl_ndc_<version>.gpkg
# - TOTAL (for mapping + QA, includes NDC flags):
#     data/<city_tag>/<city_tag>_ci_osmextract_custom_total_<version>.gpkg
#     Columns used for overlays: ndc_keep (TRUE/FALSE), ndc_pass ("p1")
#
# Nothing is deleted: "duplicates" are flagged in TOTAL and optionally shown as an
# overlay layer (ndc_keep == FALSE).
# ================================================================

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(leaflet)
})

# -----------------------------
# Palettes (ORDER MATTERS)
# -----------------------------
# Align osmextract_custom colours with intended meaning:
# - strong_ci   -> Separated cycling infrastructure (greens)
# - moderate_ci -> Painted on-road cycle lane (red)
# - weak_ci     -> Mixed traffic (cars / buses) (blue)
# - shared_foot -> Cycling on pedestrian infrastructure (yellow)
pal_osmextract <- c(
  strong_ci   = "#054d05",
  moderate_ci = "#1A7832",
  weak_ci     = "#AFD4A0",
  shared_foot = "#ebc0d4"
)

# Only base classes go into the main legend/order
pal_osmextract_base <- pal_osmextract

# --- NDC overlay label (p1 only) ---
NDC_LABEL_P1 <- "Flagged duplicate (near cycleway)"

# Optional overlay colours (currently NDC flags only)
pal_overlays <- c(
  NDC_LABEL_P1 = "#ffb3b3"
)

# osmactive fallback only if the package palette cannot be obtained
pal_osmactive_fallback <- c(
  "Segregated Track (wide)"   = "#054d05",
  "Off Road Path"             = "#1A7832",
  "Segregated Track (narrow)" = "#054d05", #"#87d668",
  "Shared Footway"            = "#ebc0d4",
  "Painted Cycle Lane"        = "#AFD4A0" #"#FF0000"
)

# "#ebc0d4", "#AFD4A0","#1A7832"

get_pal <- function(method = c("osmextract_custom", "osmactive")) {
  method <- match.arg(method)
  if (method == "osmextract_custom") return(pal_osmextract_base)
  
  if (requireNamespace("osmactive", quietly = TRUE) &&
      exists("get_palette_npt", where = asNamespace("osmactive"), inherits = FALSE)) {
    # pal <- osmactive::get_palette_npt()
    pal = pal_osmactive_fallback
    pal <- pal[!is.na(names(pal)) & nzchar(names(pal))]
    return(pal)
  }
  
  pal_osmactive_fallback
}

# -----------------------------
# Geometry guard
# -----------------------------
.keep_lines_only <- function(x, src = "") {
  if (!inherits(x, "sf") || !nrow(x)) return(x)
  
  gt <- sf::st_geometry_type(x)
  x  <- x[gt %in% c("LINESTRING", "MULTILINESTRING"), , drop = FALSE]
  
  if (!nrow(x)) {
    stop(
      "No line geometries to map",
      if (nzchar(src)) paste0(" in ", src) else "",
      ". Found: ", paste(unique(gt), collapse = ", ")
    )
  }
  
  x <- suppressWarnings(sf::st_cast(x, "LINESTRING"))
  x <- x[!sf::st_is_empty(x), , drop = FALSE]
  x
}

# -----------------------------
# Readers
# -----------------------------
read_cycling_network <- function(method = c("osmextract_custom", "osmactive"),
                                 version,
                                 city_tag = get("city_tag", envir = .GlobalEnv),
                                 crs_out = 4326) {
  method <- match.arg(method)
  
  city_dir <- file.path("data", city_tag)
  
  fname <- if (method == "osmextract_custom") {
    paste0(city_tag, "_ci_osmextract_custom_excl_ndc_", version, ".gpkg")
  } else {
    paste0(city_tag, "_ci_osmactive_", version, ".gpkg")
  }
  
  path <- file.path(city_dir, fname)
  
  if (!file.exists(path)) {
    stop(
      "Network file not found: ", path, "\n",
      "Tip: check city_tag and version, and list files in: ", city_dir,
      call. = FALSE
    )
  }
  
  x <- sf::st_read(path, quiet = TRUE) |>
    sf::st_make_valid() |>
    sf::st_transform(crs_out)
  
  .keep_lines_only(x, src = basename(path))
}

# TOTAL file (osmextract_custom only) - used to derive overlays from flags
read_cycling_total <- function(version,
                               city_tag = get("city_tag", envir = .GlobalEnv),
                               crs_out = 4326) {
  city_dir <- file.path("data", city_tag)
  fname <- paste0(city_tag, "_ci_osmextract_custom_total_", version, ".gpkg")
  path  <- file.path(city_dir, fname)
  
  if (!file.exists(path)) {
    stop(
      "TOTAL file not found: ", path, "\n",
      "Tip: run R/02_ci_osmextract_custom.R to generate *_total_* outputs.",
      call. = FALSE
    )
  }
  
  x <- sf::st_read(path, quiet = TRUE) |>
    sf::st_make_valid() |>
    sf::st_transform(crs_out)
  
  .keep_lines_only(x, src = basename(path))
}

# -----------------------------
# Prep (adds cls + cls_disp + col_hex)
# -----------------------------
.norm_key <- function(z) trimws(as.character(z))

pretty_osmextract_cls <- function(x) {
  x <- .norm_key(x)
  dplyr::case_when(
    x == "strong_ci"   ~ "Separated cycling infrastructure",
    x == "moderate_ci" ~ "Painted on-road cycle lane",
    x == "weak_ci"     ~ "Mixed traffic (cars / buses)",
    x == "shared_foot" ~ "Cycling on pedestrian infrastructure",
    TRUE               ~ x
  )
}

prep_for_map <- function(dat, method = c("osmextract_custom", "osmactive"), only_cls = NULL) {
  method <- match.arg(method)
  pal    <- get_pal(method)
  
  cls_col <- if (method == "osmextract_custom") {
    "cycle_cat"
  } else {
    if ("infra5" %in% names(dat)) "infra5" else "cycle_segregation"
  }
  if (!cls_col %in% names(dat)) stop("Missing classification column: ", cls_col)
  
  dat <- dat |>
    dplyr::mutate(cls = .norm_key(.data[[cls_col]])) |>
    dplyr::filter(!is.na(.data$cls) & nzchar(.data$cls))
  
  if (method == "osmextract_custom") {
    dat <- dat |> dplyr::mutate(cls_disp = pretty_osmextract_cls(.data$cls))
  } else {
    dat <- dat |> dplyr::mutate(cls_disp = .data$cls)
  }
  
  if (!is.null(only_cls)) {
    only_cls <- .norm_key(only_cls)
    dat <- dat |> dplyr::filter(.data$cls %in% only_cls)
  }
  
  pal_keys <- .norm_key(names(pal))
  pal_map  <- setNames(unname(pal), pal_keys)
  
  dat <- dat |>
    dplyr::mutate(col_hex = unname(pal_map[.norm_key(.data$cls)])) |>
    dplyr::filter(!is.na(.data$col_hex) & nzchar(.data$col_hex))
  
  if (!nrow(dat)) {
    stop(
      "0 features after prep_for_map().\n",
      "Check that your classes match the palette names.\n",
      "Try: sort(unique(dat[[cls_col]])) and names(get_pal(method))."
    )
  }
  
  dat
}

# -----------------------------
# Popups: add OSM id (click in map and copy id)
# -----------------------------
add_osmid_to_popup <- function(x) {
  if (!inherits(x, "sf") || !nrow(x)) return(x)
  
  id_col <- if ("osm_id" %in% names(x)) {
    "osm_id"
  } else if ("osm_way_id" %in% names(x)) {
    "osm_way_id"
  } else if ("osm_id.x" %in% names(x)) {
    "osm_id.x"
  } else {
    NA_character_
  }
  
  if (is.na(id_col)) return(x)
  
  if (!"popup" %in% names(x) || all(is.na(x$popup))) x$popup <- ""
  
  x$popup <- paste0(
    x$popup,
    "<br/><b>osm_id:</b> ", as.character(x[[id_col]])
  )
  
  x
}

# -----------------------------
# NDC overlay prep (from TOTAL flags)
# -----------------------------
prep_ndc_flagged_for_map <- function(dat_total,
                                     pass = c("p1"),
                                     label = NDC_LABEL_P1) {
  pass <- match.arg(pass)
  
  if (!inherits(dat_total, "sf") || !nrow(dat_total)) return(dat_total[0, , drop = FALSE])
  if (!all(c("ndc_pass", "ndc_keep") %in% names(dat_total))) return(dat_total[0, , drop = FALSE])
  
  ndc <- dat_total[
    !is.na(dat_total$ndc_keep) & (dat_total$ndc_keep == FALSE) &
      !is.na(dat_total$ndc_pass) & (as.character(dat_total$ndc_pass) == pass),
    , drop = FALSE
  ]
  if (!nrow(ndc)) return(ndc)
  
  ndc$cls <- label
  
  col <- unname(pal_overlays[label])
  if (is.na(col) || !nzchar(col)) col <- "#111111"
  ndc$col_hex <- col
  
  orig <- if ("cycle_cat" %in% names(ndc)) pretty_osmextract_cls(ndc$cycle_cat) else NA_character_
  
  ndc$popup <- paste0(
    "<b>flag:</b> ", label, "<br/>",
    "<b>rule:</b> overlaps cycleway buffer (15 m; ≥20 m and ≥50% length)<br/>",
    if (!all(is.na(orig))) paste0("<b>tag class:</b> ", orig) else ""
  )
  
  ndc
}

# -----------------------------
# GSV popups (safe for lines)
# -----------------------------
add_gsv_popup_safe <- function(x, add_gsv = TRUE, label = "class", crs_xy = 3857) {
  if (!inherits(x, "sf") || !nrow(x)) return(x)
  
  if (!"cls" %in% names(x)) x$cls <- NA_character_
  if (!"popup" %in% names(x)) x$popup <- paste0("<b>", label, ":</b> ", x$cls)
  
  if (!isTRUE(add_gsv)) return(x)
  
  x_m <- sf::st_transform(x, crs_xy)
  
  pts_list <- vector("list", nrow(x_m))
  for (i in seq_len(nrow(x_m))) {
    gi <- sf::st_geometry(x_m)[i]
    
    pi <- try(suppressWarnings(sf::st_line_sample(gi, sample = 0.5)), silent = TRUE)
    
    if (inherits(pi, "try-error") || length(pi) == 0) {
      bb <- sf::st_bbox(gi)
      pi <- sf::st_sfc(
        sf::st_point(c(mean(bb[c("xmin","xmax")]), mean(bb[c("ymin","ymax")]))),
        crs = crs_xy
      )
    }
    
    pi <- suppressWarnings(sf::st_cast(pi, "POINT"))
    if (length(pi) == 0) {
      bb <- sf::st_bbox(gi)
      pi <- sf::st_sfc(
        sf::st_point(c(mean(bb[c("xmin","xmax")]), mean(bb[c("ymin","ymax")]))),
        crs = crs_xy
      )
    }
    
    pts_list[[i]] <- pi[1]
  }
  
  pts_m  <- do.call(c, pts_list)
  pts_ll <- sf::st_transform(pts_m, 4326)
  xy     <- sf::st_coordinates(pts_ll)
  
  x$gsv_url <- paste0("https://www.google.com/maps?layer=c&cbll=", xy[, 2], ",", xy[, 1])
  x$popup <- paste0(
    x$popup,
    "<br/><a href='", x$gsv_url, "' target='_blank'>Open Street View</a>"
  )
  
  x
}

# -----------------------------
# Legends
# -----------------------------
.add_present_legend <- function(m, dat, method,
                                position = "bottomleft",
                                title = "Classes") {
  if (!inherits(dat, "sf") || !nrow(dat)) return(m)
  if (!all(c("cls", "col_hex") %in% names(dat))) return(m)
  
  pal <- get_pal(method)
  present_keys <- unique(.norm_key(dat$cls))
  
  leg <- dplyr::tibble(
    cls_label = names(pal),
    key       = .norm_key(names(pal)),
    col_hex   = unname(pal)
  )
  
  if (method == "osmextract_custom") {
    leg <- leg |> dplyr::mutate(cls_label = pretty_osmextract_cls(.data$key))
  }
  
  leg <- leg |> dplyr::filter(.data$key %in% present_keys)
  if (!nrow(leg)) return(m)
  
  leaflet::addLegend(
    m,
    position = position,
    colors   = leg$col_hex,
    labels   = leg$cls_label,
    title    = title,
    opacity  = 1
  )
}

.add_overlay_legend <- function(m, overlay_all, position = "bottomright") {
  if (!inherits(overlay_all, "sf") || !nrow(overlay_all)) return(m)
  if (!all(c("cls", "col_hex") %in% names(overlay_all))) return(m)
  
  present <- unique(as.character(overlay_all$cls))
  order <- names(pal_overlays)
  present <- intersect(order, present)
  if (!length(present)) return(m)
  
  cols <- unname(pal_overlays[present])
  cols[is.na(cols) | !nzchar(cols)] <- "#111111"
  
  leaflet::addLegend(
    m,
    position = position,
    colors   = cols,
    labels   = present,
    title    = "Overlays",
    opacity  = 1
  )
}

# -----------------------------
# Add overlay groups
# -----------------------------
.add_by_class <- function(m, dat, year_label,
                          class_order,
                          weight = 3, opacity = 0.9) {
  if (!inherits(dat, "sf") || !nrow(dat)) return(m)
  if (!all(c("cls", "col_hex", "popup") %in% names(dat))) return(m)
  
  cls_vals <- intersect(class_order, unique(dat$cls))
  
  for (cl in cls_vals) {
    sub <- dat[dat$cls == cl, , drop = FALSE]
    if (!nrow(sub)) next
    
    cl_disp <- if ("cls_disp" %in% names(sub)) unique(sub$cls_disp)[1] else cl
    grp <- paste0(year_label, " | ", cl_disp)
    
    m <- leaflet::addPolylines(
      m,
      data    = sub,
      color   = ~col_hex,
      weight  = weight,
      opacity = opacity,
      popup   = ~popup,
      group   = grp
    )
  }
  m
}

.add_overlay_group <- function(m, dat_overlay, year_label, group_label,
                               weight = 4, opacity = 0.9) {
  if (!inherits(dat_overlay, "sf") || !nrow(dat_overlay)) return(m)
  
  grp <- paste0(year_label, " | ", group_label)
  
  leaflet::addPolylines(
    m,
    data    = dat_overlay,
    color   = ~col_hex,
    weight  = weight,
    opacity = opacity,
    popup   = ~popup,
    group   = grp
  )
}

# -----------------------------
# Main map
# -----------------------------
map_cycling_leaf_multi_year <- function(method = c("osmextract_custom", "osmactive"),
                                        versions, # Now a vector: c("v1", "v2", "v3", ...)
                                        city_tag = get("city_tag", envir = .GlobalEnv),
                                        city_name = NULL,
                                        add_gsv = TRUE,
                                        show_legend = TRUE,
                                        legend_position = "bottomleft",
                                        only_cls = NULL,
                                        show_ndc = TRUE) {
  method <- match.arg(method)
  if (is.null(city_name)) city_name <- city_tag
  
  pal <- get_pal(method)
  class_order <- names(pal)
  
  # Initialize the map
  m <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE)) |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron)
  
  all_groups <- character(0)
  bbox_collector <- list()
  legend_data_collector <- list()
  overlay_data_collector <- list()
  
  # --- LOOP THROUGH EACH VERSION ---
  for (i in seq_along(versions)) {
    v <- versions[i]
    v_lab <- as.character(v)
    
    # 1. Read and Prep Base Network
    d_raw <- read_cycling_network(method, v, city_tag)
    d <- d_raw |>
      prep_for_map(method = method, only_cls = only_cls) |>
      dplyr::mutate(popup = paste0("<b>class:</b> ", .data$cls_disp)) |>
      add_osmid_to_popup() |>
      add_gsv_popup_safe(add_gsv = add_gsv, label = "class")
    
    # Track for legend and bounding box
    bbox_collector[[length(bbox_collector) + 1]] <- d[, 0]
    legend_data_collector[[length(legend_data_collector) + 1]] <- d
    
    # 2. Add Base layers to map by class
    m <- .add_by_class(m, d, v_lab, class_order = class_order)
    
    # Calculate group names for the controller
    base_keys <- intersect(class_order, unique(d$cls))
    labs <- vapply(base_keys, function(k) unique(d$cls_disp[d$cls == k])[1], character(1))
    v_groups <- paste0(v_lab, " | ", labs)
    all_groups <- c(all_groups, v_groups)
    
    # 3. Handle Overlays (NDC)
    if (method == "osmextract_custom" && isTRUE(show_ndc)) {
      tot_raw <- read_cycling_total(v, city_tag)
      bbox_collector[[length(bbox_collector) + 1]] <- tot_raw[, 0]
      
      ndc_p1 <- prep_ndc_flagged_for_map(tot_raw, pass = "p1", label = NDC_LABEL_P1) |>
        add_osmid_to_popup() |>
        add_gsv_popup_safe(add_gsv = add_gsv, label = "flag")
      
      if (inherits(ndc_p1, "sf") && nrow(ndc_p1)) {
        overlay_grp <- paste0(v_lab, " | ", NDC_LABEL_P1)
        m <- .add_overlay_group(m, ndc_p1, v_lab, NDC_LABEL_P1)
        all_groups <- c(all_groups, overlay_grp)
        overlay_data_collector[[length(overlay_data_collector) + 1]] <- ndc_p1
      }
    }
    
    # 4. Logic: Hide all but the FIRST version by default
    if (i > 1) {
      for (grp in v_groups) m <- leaflet::hideGroup(m, grp)
      # Also hide the NDC group if it exists for this version
      m <- leaflet::hideGroup(m, paste0(v_lab, " | ", NDC_LABEL_P1))
    }
  }
  
  # --- Final Map Adjustments ---
  
  # Set view based on all data
  combined_bb <- sf::st_bbox(dplyr::bind_rows(bbox_collector))
  m <- m |> leaflet::fitBounds(combined_bb[["xmin"]], combined_bb[["ymin"]], 
                               combined_bb[["xmax"]], combined_bb[["ymax"]])
  
  # Add Controls
  m <- m |> leaflet::addLayersControl(
    overlayGroups = all_groups,
    options = leaflet::layersControlOptions(collapsed = TRUE)
  )
  
  if (requireNamespace("leaflet.extras", quietly = TRUE)) {
    m <- leaflet.extras::addFullscreenControl(m, position = "topleft")
  }
  
  # Add Legends
  if (isTRUE(show_legend)) {
    m <- .add_present_legend(m, dat = dplyr::bind_rows(legend_data_collector), 
                             method = method, position = legend_position)
    
    if (length(overlay_data_collector) > 0) {
      m <- .add_overlay_legend(m, dplyr::bind_rows(overlay_data_collector), position = "bottomright")
    }
  }
  
  return(m)
}


map_cycling_switcher <- function(method = c("osmextract_custom", "osmactive"),
                                 versions, 
                                 city_tag = get("city_tag", envir = .GlobalEnv),
                                 city_name = NULL,
                                 only_cls = NULL) {
  
  method <- match.arg(method)
  pal <- get_pal(method)
  class_order <- names(pal)
  
  m <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE)) |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron)
  
  # We will store the name of the 'Year' groups to use as radio buttons
  year_base_groups <- as.character(versions)
  
  for (v in versions) {
    v_lab <- as.character(v)
    
    # 1. Read and Prep
    d_raw <- read_cycling_network(method, v, city_tag)
    d <- d_raw |>
      prep_for_map(method = method, only_cls = only_cls) |>
      dplyr::mutate(popup = paste0("<b>Year: ", v_lab, "</b><br><b>Class:</b> ", .data$cls_disp)) |>
      add_osmid_to_popup() |>
      add_gsv_popup_safe(add_gsv = TRUE)
    
    # 2. Add to Map
    # We use the same 'group' name (the year) for ALL infrastructure in that year
    # This allows us to toggle the whole year at once.
    m <- m |> leaflet::addPolylines(
      data = d,
      color = ~col_hex,
      weight = 3,
      opacity = 0.8,
      popup = ~popup,
      group = v_lab  # This is key: the group is just the Year
    )
  }
  
  # 3. Add Layer Control as "baseGroups"
  # baseGroups act like radio buttons (only one active at a time)
  m <- m |> leaflet::addLayersControl(
    baseGroups = year_base_groups,
    options = leaflet::layersControlOptions(collapsed = FALSE)
  )
  
  # 4. Add Legend (Shared across all years)
  m <- .add_present_legend(m, dat = d, method = method, title = "Infrastructure Type")
  
  return(m)
}


# map_cycling_leaf_two_years("osmactive", "210101", "260101")
map_cycling_leaf_multi_year("osmextract", city_tag = "lisbon", versions = VERSIONS)
map_cycling_switcher("osmextract", city_tag = "lisbon", versions = VERSIONS)

map_cycling_switcher("osmextract", city_tag = "sydney", versions = VERSIONS)
