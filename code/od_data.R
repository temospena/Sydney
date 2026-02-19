# ODs

# There are many ways of define the ODs.
# For this research, maybe using a grid h3 as all origins and destinations is enough?

# Consider another way of doing this, with jittering? weighted by buildings heights?


# h3 grid ---------------------isothropic -------------------------
library(h3jsr)

# h3_res = 10 # 150m diameter
# h3_res = 9 # 400m diameter
h3_res = 8 # 1060m diameter

## Lisbon
lisbon_limit = st_read("data/lisbon/lisbon_perimeter.gpkg") 
lisbon_grid = lisbon_limit |>  
  polygon_to_cells(res = h3_res, simple = FALSE)
lisbon_grid = lisbon_grid$h3_addresses |>
  cell_to_polygon(simple = FALSE)
lisbon_grid = lisbon_grid |>
  mutate(id = seq(1:nrow(lisbon_grid)))  # give an ID to each cell
lisbon_h3_index = lisbon_grid |> st_drop_geometry() # save h3_address for later

nrow(lisbon_grid) # 754
# ods_all_res9 = 568.516
# ods_all_res8 = 12.100
mapview(lisbon_grid)


## Sydney
sydney_limit = st_read("data/sydney/sydney_perimeter.gpkg") 
sydney_grid = sydney_limit |>  
  polygon_to_cells(res = h3_res, simple = FALSE)
sydney_grid = sydney_grid$h3_addresses |>
  cell_to_polygon(simple = FALSE)
sydney_grid = sydney_grid |>
  mutate(id = seq(1:nrow(sydney_grid)))  # give an ID to each cell
sydney_h3_index = sydney_grid |> st_drop_geometry() # save h3_address for later

nrow(sydney_grid) # 30
# ods_all_res8 = 900
mapview(sydney_grid)


## Paris
paris_limit = st_read("data/paris/paris_perimeter.gpkg") 
paris_grid = paris_limit |>  
  polygon_to_cells(res = h3_res, simple = FALSE)
paris_grid = paris_grid$h3_addresses |>
  cell_to_polygon(simple = FALSE)
paris_grid = paris_grid |>
  mutate(id = seq(1:nrow(paris_grid)))  # give an ID to each cell
paris_h3_index = paris_grid |> st_drop_geometry() # save h3_address for later

nrow(paris_grid) # 164
# ods_all_res8 = 26.896
mapview(paris_grid)



# with buildngs as O and D ------------------------------------------------

city = "lisbon" # change here

# piggyback::pb_download(file = "lisbon_city_buildings.geojson", dest = "data/lisbon/")
buildings = st_read("data/lisbon/lisbon_city_buildings.geojson")


set.seed(42)
buildings_sample20k_DE = buildings |> 
  slice_sample(
    n = 20000, 
    weight_by = total_floor_area_m2, # use this as proxy for jobs or schools destinations (higher volumes) - not sure if it is making a difference
    replace = TRUE
  ) |> 
  select(total_floor_area_m2) |> 
  rename(volume = total_floor_area_m2)
destinations_lisbon = buildings_sample20k_DE |> mutate(id = 1:nrow(buildings_sample20k_DE))
  

buildings_sample20k_OR = buildings |> 
  slice_sample(
    n = 20000, # not weighted?
    replace = TRUE
  ) |> 
  select(total_floor_area_m2) |> 
  rename(volume = total_floor_area_m2)
origins_lisbon = buildings_sample20k_OR |> mutate(id = 1:nrow(buildings_sample20k_OR))

library(mapview)
mapview(origins_lisbon, zcol= "id" )
mapview(destinations_lisbon, zcol= "id" )
# they are randomly distributed, so I can make OD by id-id

st_write(origins_lisbon, "networks/r5r/origins_lisbon.gpkg", delete_dsn = TRUE)
st_write(destinations_lisbon, "networks/r5r/destinations_lisbon.gpkg", delete_dsn = TRUE)
