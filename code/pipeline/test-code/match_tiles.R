library(dplyr)
library(sf)
library(stringr)

city_list <- read.csv("data/city_list.txt", header = FALSE) |>
  rename(
      city = V1,
      lat = V2,
      lon = V3,
      population = V4,
      country = V5,
      country_code = V6
  ) |>
  st_as_sf(crs = 4326, coords = c("lon", "lat"))

lod1 <- st_read("data/lod1.geojson", quiet = TRUE)
sf_use_s2(FALSE)

city_list_joined <- st_join(city_list, lod1, join = st_intersects)

# tile is stored in $tile like "europe/e010_n50_e015_n45"
# we just need the basename
city_list_out <- city_list_joined |>
  mutate(
      buildings_tile = basename(as.character(tile)) # e.g. "e010_n50_e015_n45"
  ) |>
  st_drop_geometry() |>
  # restore original lon/lat just like it was before
  # but since st_drop_geometry removes coords, let's keep coords from original
  bind_cols(st_coordinates(city_list) |> as.data.frame() |> rename(lon = X, lat = Y))

# reorder
city_list_out <- city_list_out |>
  select(city, lat, lon, population, country, country_code, buildings_tile)

write.table(city_list_out, "data/city_list.txt", row.names = FALSE, col.names = FALSE, sep = ",")
cat("city_list.txt updated with buildings_tile.\n")
