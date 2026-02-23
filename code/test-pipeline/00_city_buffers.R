# 00_city_buffers.R

library(dplyr)
library(sf)
sf_use_s2(TRUE)

# Define directories
data_dir <- path.expand("~/GIS/Sydney/data")
output_dir <- file.path(data_dir, "test-pipeline")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Read the full dataset
city_list <- read.csv(file.path(data_dir, "city_list.txt"), header = FALSE)
city_list <- city_list |>
    rename(
        city = V1,
        lat = V2,
        lon = V3,
        population = V4,
        country = V5,
        country_code = V6
    ) |>
    st_as_sf(crs = 4326, coords = c("lon", "lat"))

# Target cities
target_cities <- c("Sydney")

city_list_target <- city_list |>
    filter(city %in% target_cities)

# Create 10km buffers from points
city_list_buf <- city_list_target |>
    st_transform(3857) |>
    st_buffer(dist = 10000) |> # 10 km
    st_transform(4326)

# Save each city
for (i in 1:nrow(city_list_buf)) {
    city_name <- tolower(city_list_buf$city[i])
    city_poly <- city_list_buf[i, ]

    city_dir <- file.path(output_dir, city_name)
    dir.create(city_dir, showWarnings = FALSE, recursive = TRUE)

    st_write(city_poly, file.path(city_dir, paste0(city_name, "_10km.gpkg")), append = FALSE, delete_dsn = TRUE, quiet = TRUE)

    # Save the bbox for osmium extraction later
    bbox <- st_bbox(city_poly)
    bbox_str <- paste(bbox["xmin"], bbox["ymin"], bbox["xmax"], bbox["ymax"], sep = ",")
    writeLines(bbox_str, file.path(city_dir, paste0(city_name, "_bbox.txt")))
}

cat("City buffers successfully exported for target cities.\n")
