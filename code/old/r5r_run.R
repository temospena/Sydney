# run detailed iteniraries for bike between the OD pairs (see od_data.R)


# lisbon ------------------------------------------------------------------


#### lts 3
## 2016
trips_lisbon_16_lts3 = detailed_itineraries(
  r5r_network = r5_lisbon16,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 3,
  # drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_16_lts3) # 19998
summary(trips_lisbon_16_lts3$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 69    4628    7188    7398    9709   21480 
summary(trips_lisbon_16_lts3$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.50   30.40   45.70   46.51   60.90  118.90 




## 2021
trips_lisbon_21_lts3 = detailed_itineraries(
  r5r_network = r5_lisbon21,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 3,
  # drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_21_lts3) # 19951
summary(trips_lisbon_21_lts3$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 69    4528    7008    7196    9442   21769 
summary(trips_lisbon_21_lts3$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.50   28.70   43.10   43.69   57.10  117.20 


## 2026
trips_lisbon_26_lts3 = detailed_itineraries(
  r5r_network = r5_lisbon26,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 3,
  # drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_26_lts3) # 19936
summary(trips_lisbon_26_lts3$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 110    4390    6784    6955    9121   21169 
summary(trips_lisbon_26_lts3$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.60   26.50   39.60   40.47   52.60  114.90 


# Combine datasets and add a year identifier
trips_lisbon_combined_lts3 <- bind_rows(
  trips_lisbon_16_lts3 %>% mutate(year = "2016"),
  trips_lisbon_21_lts3 %>% mutate(year = "2021"),
  trips_lisbon_26_lts3 %>% mutate(year = "2026")
) %>%
  mutate(year = as.factor(year))

saveRDS(trips_lisbon_combined_lts3, "networks/results_ttm/trips_lisbon_lts3_geo.rds")
saveRDS(trips_lisbon_combined_lts3 |> st_drop_geometry(), "networks/results_ttm/trips_lisbon_lts3.rds")



#### lts 2
## 2016
trips_lisbon_16_lts2 = detailed_itineraries(
  r5r_network = r5_lisbon16,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 2,
  # drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_16_lts2) # 19882
summary(trips_lisbon_16_lts2$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 69    4759    7448    7610   10120   20250 
summary(trips_lisbon_16_lts2$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.50   36.30   53.95   54.97   72.80  120.00 




## 2021
trips_lisbon_21_lts2 = detailed_itineraries(
  r5r_network = r5_lisbon21,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 2,
  # drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_21_lts2) # 19928
summary(trips_lisbon_21_lts2$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 69    4645    7237    7411    9789   20571 
summary(trips_lisbon_21_lts2$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.50   32.00   47.80   48.46   63.10  119.70 


## 2026
trips_lisbon_26_lts2 = detailed_itineraries(
  r5r_network = r5_lisbon26,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 2,
  # drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_26_lts2) # 19934
summary(trips_lisbon_26_lts2$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 110    4517    6977    7171    9412   20815 
summary(trips_lisbon_26$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.60   29.00   43.50   44.36   57.70  119.00 


# Combine datasets and add a year identifier
trips_lisbon_combined_lts2 <- bind_rows(
  trips_lisbon_16_lts2 %>% mutate(year = "2016"),
  trips_lisbon_21_lts2 %>% mutate(year = "2021"),
  trips_lisbon_26_lts2 %>% mutate(year = "2026")
) %>%
  mutate(year = as.factor(year))

saveRDS(trips_lisbon_combined_lts2, "networks/results_ttm/trips_lisbon_lts2_geo.rds")
saveRDS(trips_lisbon_combined_lts2 |> st_drop_geometry(), "networks/results_ttm/trips_lisbon_lts2.rds")



# map with overline -------------------------------------------------------

library(tidyverse)
library(sf)
library(stplanr)
library(tmap, lib.loc = "/usr/lib/R/site-lib") # v4
tmap_mode("view")

trips_overline = trips_lisbon_combined_lts2 |> mutate(trips = 1)
# trips_overline = trips_lisbon_combined_lts3 |> mutate(trips = 1)

map_data <- trips_overline %>%
  group_split(year) %>%
  map_dfr(function(year_data) {
    overline2(year_data, attrib = "trips") %>%
      mutate(year = unique(year_data$year))
  }) |> 
  filter(trips > 1)

saveRDS(map_data, "networks/results_ttm/lisbon_lts2_overline.rds")
# saveRDS(map_data, "networks/results_ttm/lisbon_lts3_overline.rds")


# map
tm_shape(map_data) +
  tm_lines(
    col = "year", 
    lwd = "trips", 
    scale = 5, # Adjust this to make lines thicker/thinner
    palette = "Set1",
    title.lwd = "Number of Trips",
    id = "trips"
  ) +
  # tm_facets(by = "year", sync = TRUE, free.coords = FALSE) # paper
  tm_facets(by = "year", as.layers = TRUE) # interactive

