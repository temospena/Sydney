# ODs

# There are many ways of dedinfint the ODs.
# For rhis research, maybe using a grid h3 as all origins and destinations is enough?

# Consider another way of doing this, with jittering? weighted by buildings heights?




# h3 grid -----------------------------------------------------------------
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
