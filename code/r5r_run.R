# run detailed iteniraries for bike between the OD pairs (see od_data.R)


# lisbon ------------------------------------------------------------------


#### lts 3
## 2016
trips_lisbon_16 = detailed_itineraries(
  r5r_network = r5_lisbon16,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 3,
  drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_16) # 19998
summary(trips_lisbon_16$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 69    4628    7188    7398    9709   21480 
summary(trips_lisbon_16$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.50   30.40   45.70   46.51   60.90  118.90 




## 2021
trips_lisbon_21 = detailed_itineraries(
  r5r_network = r5_lisbon21,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 3,
  drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_21) # 19951
summary(trips_lisbon_21$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 69    4528    7008    7196    9442   21769 
summary(trips_lisbon_21$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.50   28.70   43.10   43.69   57.10  117.20 


## 2026
trips_lisbon_26 = detailed_itineraries(
  r5r_network = r5_lisbon26,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 3,
  drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_26) # 19936
summary(trips_lisbon_26$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 110    4390    6784    6955    9121   21169 
summary(trips_lisbon_26$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.60   26.50   39.60   40.47   52.60  114.90 


#### lts 2
## 2016
trips_lisbon_16 = detailed_itineraries(
  r5r_network = r5_lisbon16,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 2,
  drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_16) # 19882
summary(trips_lisbon_16$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 69    4759    7448    7610   10120   20250 
summary(trips_lisbon_16$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.50   36.30   53.95   54.97   72.80  120.00 




## 2021
trips_lisbon_21 = detailed_itineraries(
  r5r_network = r5_lisbon21,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 2,
  drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_21) # 19928
summary(trips_lisbon_21$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 69    4645    7237    7411    9789   20571 
summary(trips_lisbon_21$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.50   32.00   47.80   48.46   63.10  119.70 


## 2026
trips_lisbon_26 = detailed_itineraries(
  r5r_network = r5_lisbon26,
  origins = origins_lisbon,
  destinations = destinations_lisbon,
  mode = "BICYCLE",
  shortest_path = TRUE,
  max_lts = 2,
  drop_geometry = TRUE,
  # osm_link_ids = TRUE, # test this later if don't have the lts
  progress = TRUE
)

nrow(trips_lisbon_26) # 19934
summary(trips_lisbon_26$distance)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 110    4517    6977    7171    9412   20815 
summary(trips_lisbon_26$total_duration)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0.60   29.00   43.50   44.36   57.70  119.00 



## WARNING - do for each LTS
# Combine datasets and add a year identifier
trips_lisbon_combined <- bind_rows(
  trips_lisbon_16 %>% mutate(year = "2016"),
  trips_lisbon_21 %>% mutate(year = "2021"),
  trips_lisbon_26 %>% mutate(year = "2026")
) %>%
  mutate(year = as.factor(year))

saveRDS(trips_lisbon_combined, "networks/results_ttm/trips_lisbon_lts3.rds")
# saveRDS(trips_lisbon_combined, "networks/results_ttm/trips_lisbon_lts2.rds")




## Compare with plot

library(dplyr)
library(ggplot2)


# cumulative travel time
ggplot(trips_lisbon_combined, aes(x = total_duration, color = year)) +
  stat_ecdf(lwd = 1.2) +
  geom_vline(xintercept = 30, linetype = "dashed", color = "gray40") +
  annotate("text", x = 32, y = 0.1, label = "30-min threshold", angle = 90) +
  scale_color_viridis_d() +
  labs(
    title = "Cumulative Travel Time Distribution",
    subtitle = "Percentage of trips completed within a travel time",
    x = "Duration (minutes)",
    y = "Proportion of all trips"
  ) +
  theme_minimal()+
    xlim(0, 125) # Cutting off outliers for better visibility


# cumulative travel distance
ggplot(trips_lisbon_combined, aes(x = distance, color = year)) +
  stat_ecdf(lwd = 1.2) +
  geom_vline(xintercept =5000, linetype = "dashed", color = "gray40") +
  annotate("text", x = 5400, y = 0.1, label = "5 km threshold", angle = 90) +
  scale_color_viridis_d() +
  labs(
    title = "Cumulative Travel Distance Distribution",
    subtitle = "Percentage of trips completed within a travel distance",
    x = "Distance (meters)",
    y = "Proportion of all trips"
  ) +
  theme_minimal()+
    xlim(0, 20000) # Cutting off outliers for better visibility

# What % of the population can reach their destination in under 30 minutes?" 
# The steeper the curve, the more accessible the city.
# The Density Plot will show that the "peak" of the distribution in 2026 is noticeably further to the left than in 2016, proving the network is becoming more efficient.
# as the cycling network evolves from 2016 to 2026, trips are becoming both shorter (lower distance) and faster (lower duration).

# # density
# ggplot(trips_lisbon_combined, aes(x = total_duration, fill = year)) +
#   geom_density(alpha = 0.5) +
#   scale_fill_viridis_d(option = "viridis", name = "Year") +
#   labs(
#     title = "Shift in Cycling Trip Durations (2016-2026)",
#     subtitle = "The network evolution shows a clear shift toward shorter travel times.",
#     x = "Duration (minutes)",
#     y = "Density"
#   ) +
#   theme_minimal() +
#   xlim(0, 100) # Cutting off outliers for better visibility
