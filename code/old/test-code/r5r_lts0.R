# test lts0 for ci

lisbon_roadnetwork_20260101 = sf::st_read("data/pipeline/lisbon/r5r_26/lisbon_26_lts.gpkg")
lisbon_ci_osmactive_20260101 = sf::st_read("data/pipeline/lisbon/lisbon_ci_osmactive_260101.gpkg")
lts0_lisbon = lisbon_ci_omsactive_20260101 |> sf::st_drop_geometry() |> select(osm_id) |> mutate(lts =0)


# r5r with lts0? does not work that way -----------------------------------


r5r_lisbon26 = r5r::build_network("data/pipeline/lisbon/r5r_26")
origins = sf::st_read("data/pipeline/lisbon/origins.gpkg")
destinations = sf::st_read("data/pipeline/lisbon/destinations.gpkg")

ttm_new_lts <- r5r::travel_time_matrix(
  r5r_network = r5r_lisbon26,
  origins = origins[1:100,],
  destinations = destinations[1:100,],
  mode = 'bicycle',
  max_trip_duration = 30,
  max_lts = 0, # wil this work?
  new_lts = lts0_lisbon # new osm with lts 0 for ci
)



# if we change them to 1 --------------------------------------------------

lts_ci_lisbon_test = lisbon_ci_omsactive_20260101 |>
  sf::st_drop_geometry() |>
  mutate(osm_id = as.integer(osm_id)) |>
  left_join(lisbon_roadnetwork_20260101 |> sf::st_drop_geometry() |> select(osm_id, bicycle_lts), by = "osm_id") |> 
  group_by(osm_id, name, highway, bicycle_lts) |>
  summarize()

table(lts_ci_lisbon_test$bicycle_lts)
# 1    2    3    4 
# 1551  146  183  324 

table(lts_ci_lisbon_test$bicycle_lts, lts_ci_lisbon_test$highway)
# 
# cycleway footway living_street path pedestrian primary residential secondary service tertiary tertiary_link
# 1      615     563             4   77          6       0         267         0      19        0             0
# 2       39      14             0    0          0       0          37         0       0       55             1
# 3       47      38             1   11          1       2          26         3       5       31             2
# 4      155      48             1    9          0      48          43         6       2        7             0
# 
# unclassified
# 1            0
# 2            0
# 3           16
# 4            5

round(prop.table(table(lts_ci_lisbon_test$bicycle_lts))*100,1)
# 1    2    3    4 
# 70.4  6.6  8.3 14.7 

# for each year,
# re-classify all the osm_id, using the r5r tag   new_lts = lts_ci_lisbon_26
# that are %in% ci_osmactive_year as lts 1, and the rest as they are in the original road network (1-4)
