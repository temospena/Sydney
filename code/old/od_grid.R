# use a standart grid for the OD estimations, instead of 20k points that requere much more computation

library(h3jsr)
library(sf)
library(dplyr)
library(mapview)
# 


# h3 resolution: https://h3geo.org/docs/core-library/restable/
h3_res = 10 # 150m diameter
# h3_res = 9 # 400m diameter
# h3_res = 8 # 1060m diameter

limit = city_list_sample_area |> filter(city == "Lisbon") # example

grid = limit |>
  polygon_to_cells(res = h3_res, simple = FALSE)
grid = grid$h3_addresses |>
  cell_to_polygon(simple = FALSE)
nrow(grid)
# mapview(grid) + mapview(grelha_tml_centroids |> st_transform(crs=4326), col.regions="red")

grid = grid |>
  mutate(id = seq(1:nrow(grid)))  # give an ID to each cell
h3_index = grid |> st_drop_geometry() # save h3_address for later

mapview(grid)


# check if buildings O and D reduce the number od 20k iterations
origins = st_read("data/pipeline/lisbon/origins.gpkg")
destinations = st_read("data/pipeline/lisbon/destinations.gpkg")


# origins
grid_origins = origins |> st_join(grid, join = st_within)

grid_origins2 = grid_origins |>
  st_drop_geometry() |>   # drop geometry for counting
  group_by(id.y) |>
  summarise(volume = sum(volume),
            trips = n(),
  ) |> 
  rename(id = id.y) |> 
  filter(!is.na(id)) |>
  ungroup()

grid_origins = grid |>
  left_join(grid_origins2, by = "id") |>
  mutate(across(where(is.numeric), ~tidyr::replace_na(.x, 0)))


# destinations
grid_destinations = destinations |> st_join(grid, join = st_within)

grid_destinations2 = grid_destinations |>
  st_drop_geometry() |>   # drop geometry for counting
  group_by(id.y) |>
  summarise(volume = sum(volume),
            trips = n(),
  ) |> 
  rename(id = id.y) |> 
  filter(!is.na(id)) |>
  ungroup()

grid_destinations = grid |>
  left_join(grid_destinations2, by = "id") |>
  mutate(across(where(is.numeric), ~tidyr::replace_na(.x, 0)))


# i feel i am almost there...


mapview(grid_destinations |> filter(trips > 0), zcol="trips")




## Grid centroids

origins_points = st_centroid(grid_origins) |> 	
  select(id, h3_address) # add also the other variables?

