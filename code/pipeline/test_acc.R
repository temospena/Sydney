options(java.parameters = "-Xmx4G") # this needs to to before the library r5r
library(r5r)
library(accessibility)
library(sf)
library(dplyr)

# trips <- readRDS("data/sydney/trips_sydney_16_lts1.rds")
r5_engine <- build_network(data_path = "data/pipeline/sydney/r5r_16", verbose = FALSE)
origins_path <- "data/pipeline/sydney/origins.gpkg"
origins <- st_read(origins_path, quiet = TRUE)
dests_path <- "data/pipeline/sydney/destinations.gpkg"
dests <- st_read(dests_path, quiet = TRUE)

# Format for r5r (requires data.frame with id, lon, lat)
origins_df <- data.frame(
    id = as.character(origins$id),
    lon = st_coordinates(origins)[, 1],
    lat = st_coordinates(origins)[, 2]
)
dests_df <- data.frame(
    id = as.character(dests$id),
    lon = st_coordinates(dests)[, 1],
    lat = st_coordinates(dests)[, 2],
    volume = dests$volume
)


trips <- detailed_itineraries(
    r5r_network = r5_engine,
    origins = origins_df,
    destinations = dests_df,
    mode = "BICYCLE",
    shortest_path = TRUE,
    max_lts = 1,
    progress = TRUE
)

print("Structure of trips:")
str(trips)
print("Names of trips:")
print(names(trips))

travel_matrix <- st_drop_geometry(trips)[, c("from_id", "to_id", "total_duration")]

# voronoy?
# dests_df_polygon <- dests |>
#    mutate(geometry = st_voronoi(st_union(st_geometry(dests)))) # voronoy takes a long time. use h3 grid instead?


# acc <- accessibility::cumulative_cutoff(
#    travel_matrix = travel_matrix,
#    land_use_data = dests_df_area, # This does not work because it is not an polygon?
#    opportunity = "volume",
#    travel_cost = "total_duration",
#    cutoff = 15
# )
# print("Structure of acc:")
# str(acc)
# print("Names of acc:")
# print(names(acc))


### The alternative would be to use r5r::accessibility() function

acc_r5r <- accessibility(
    r5r_network = r5_engine,
    origins = origins_df,
    destinations = dests_df,
    opportunities = "volume",
    cutoff = 15,
    mode = "BICYCLE",
    max_lts = 1,
    progress = TRUE
)

summary(acc_r5r$accessibility)
