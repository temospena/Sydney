library(sf)

# Function from my thought process
get_tile_names_for_bbox <- function(bbox) {
    # bbox: xmin, ymin, xmax, ymax
    lon_steps <- seq(floor(bbox["xmin"] / 5) * 5, length.out = ceiling((bbox["xmax"] - bbox["xmin"]) / 5) + 1, by = 5)
    lat_steps <- seq(floor(bbox["ymin"] / 5) * 5, length.out = ceiling((bbox["ymax"] - bbox["ymin"]) / 5) + 1, by = 5)

    # Actually wait, seq might be wrong if range is small.
    # Better:
    lon_min_tile <- floor(bbox["xmin"] / 5) * 5
    lon_max_tile <- floor(bbox["xmax"] / 5) * 5
    lat_min_tile <- floor(bbox["ymin"] / 5) * 5
    lat_max_tile <- floor(bbox["ymax"] / 5) * 5

    lon_vals <- seq(lon_min_tile, lon_max_tile, by = 5)
    lat_vals <- seq(lat_min_tile, lat_max_tile, by = 5)

    tiles <- c()
    for (ln in lon_vals) {
        for (lt in lat_vals) {
            xmin <- ln
            xmax <- ln + 5
            ymin <- lt
            ymax <- lt + 5

            # Format: e/wXXX_n/sYY_e/wXXX_n/sYY
            # Hamburg: e005_n55_e010_n50
            # xmin=5, ymax=55, xmax=10, ymin=50
            tile <- paste0(
                if (xmin < 0) "w" else "e", sprintf("%03d", abs(xmin)), "_",
                if (ymax < 0) "s" else "n", sprintf("%02d", abs(ymax)), "_",
                if (xmax < 0) "w" else "e", sprintf("%03d", abs(xmax)), "_",
                if (ymin < 0) "s" else "n", sprintf("%02d", abs(ymin))
            )
            tiles <- c(tiles, tile)
        }
    }
    return(unique(tiles))
}

# Hamburg check
hamburg_bbox <- c(xmin = 9.9, ymin = 53.4, xmax = 10.1, ymax = 53.6)
cat("Hamburg tiles:\n")
print(get_tile_names_for_bbox(hamburg_bbox))

# Sydney check
sydney_bbox <- c(xmin = 151.1, ymin = -34.0, xmax = 151.3, ymax = -33.8)
cat("Sydney tiles:\n")
print(get_tile_names_for_bbox(sydney_bbox))
