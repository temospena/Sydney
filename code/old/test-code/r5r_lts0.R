# test lts0 for ci

lisbon_ci_osmactive_20160101 = sf::st_read("data/pipeline/lisbon/lisbon_ci_osmactive_260101.gpkg")
lts0_lisbon = lisbon_ci_omsactive_20260101 |> sf::st_drop_geometry() |> select(osm_id) |> mutate(lts =0)

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