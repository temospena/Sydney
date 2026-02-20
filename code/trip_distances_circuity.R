# assess distances and travel times


# compare with commulative distribution plot ------------------------------

library(dplyr)
library(ggplot2)


# trips_lisbon_combined = trips_lisbon_combined_lts2 |> st_drop_geometry()
trips_lisbon_combined = trips_lisbon_combined_lts3 |> st_drop_geometry()

# cumulative travel time
ggplot(trips_lisbon_combined, aes(x = total_duration, color = year)) +
  stat_ecdf(lwd = 1.2) +
  geom_vline(xintercept = 30, linetype = "dashed", color = "gray40") +
  annotate("text", x = 32, y = 0.87, label = "30-min threshold", angle = 90) +
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
  annotate("text", x = 5400, y = 0.87, label = "5 km threshold", angle = 90) +
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



# identify major differences ----------------------------------------------


