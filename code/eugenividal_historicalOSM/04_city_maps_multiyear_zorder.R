suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(leaflet)
})

# -----------------------------
# 1. Palettes & Priorities
# -----------------------------
# We define the order here. The LAST item in this list draws on TOP.
infra_hierarchy <- c(
  "shared_foot" = 1,
  "weak_ci"     = 2,
  "moderate_ci" = 3,
  "strong_ci"   = 4
)

pal_osmextract <- c(
  shared_foot = "#ebc0d4", # Bottom
  weak_ci     = "#AFD4A0",
  moderate_ci = "#1A7832",
  strong_ci   = "#054d05"  # Top
)

# -----------------------------
# 2. Refined Prep Function
# -----------------------------
prep_for_map <- function(dat, method = c("osmextract_custom", "osmactive"), only_cls = NULL) {
  method <- match.arg(method)
  
  cls_col <- if (method == "osmextract_custom") "cycle_cat" else "infra5"
  
  dat <- dat |>
    dplyr::mutate(cls = trimws(as.character(.data[[cls_col]]))) |>
    dplyr::filter(!is.na(cls) & nzchar(cls))
  
  # Apply hierarchy/priority for Z-index
  dat <- dat |>
    dplyr::mutate(prio = infra_hierarchy[cls]) |>
    dplyr::mutate(prio = tidyr::replace_na(prio, 0)) |>
    dplyr::arrange(prio) # Sorting ensures Leaflet draws them in this order
  
  if (method == "osmextract_custom") {
    dat <- dat |> dplyr::mutate(cls_disp = pretty_osmextract_cls(cls))
  } else {
    dat <- dat |> dplyr::mutate(cls_disp = cls)
  }
  
  if (!is.null(only_cls)) dat <- dat |> dplyr::filter(cls %in% only_cls)
  
  # Map colors
  dat$col_hex <- pal_osmextract[dat$cls]
  
  dat |> dplyr::filter(!is.na(col_hex))
}

# -----------------------------
# 3. Enhanced Multi-Year Switcher
# -----------------------------
map_cycling_multi_year <- function(versions, 
                                   city_tag = get("city_tag", envir = .GlobalEnv),
                                   method = "osmextract_custom") {
  
  m <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE)) |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron)
  
  all_years <- as.character(versions)
  bbox_list <- list()
  
  for (i in seq_along(all_years)) {
    year_val <- all_years[i]
    
    # Load and Prep
    dat <- read_cycling_network(method, year_val, city_tag) |>
      prep_for_map(method = method) |> 
      add_osmid_to_popup() |> 
      add_gsv_popup_safe(add_gsv = TRUE)
    
    bbox_list[[i]] <- dat
    
    # Add to map
    # Note: Because 'dat' is sorted by 'prio', the addPolylines 
    # call respects the Z-index automatically within the group.
    m <- m |> leaflet::addPolylines(
      data = dat,
      color = ~col_hex,
      weight = ~ifelse(cls == "strong_ci", 4, 2.5), # Stronger paths are thicker
      opacity = 0.9,
      popup = ~popup,
      group = year_val
    )
  }
  
  # Add Radio Button Controls (baseGroups)
  m <- m |> leaflet::addLayersControl(
    baseGroups = all_years,
    options = leaflet::layersControlOptions(collapsed = FALSE),
    position = "topright"
  )
  
  # Fit bounds to the first year's data
  if(length(bbox_list) > 0) {
    bb <- sf::st_bbox(bbox_list[[1]])
    m <- m |> leaflet::fitBounds(bb[[1]], bb[[2]], bb[[3]], bb[[4]])
  }
  
  # Add Legend
  m <- .add_present_legend(m, dat = bbox_list[[1]], method = method, title = "Infrastructure")
  
  return(m)
}

map_cycling_multi_year(versions = VERSIONS,  city_tag = "lisbon", method = "osmextract_custom")
map_cycling_multi_year(versions = VERSIONS,  city_tag = "sydney", method = "osmextract_custom")
