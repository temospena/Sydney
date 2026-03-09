# assess distances and travel times


# compare with commulative distribution plot ------------------------------

library(dplyr)
library(ggplot2)


trips_lisbon_combined = trips_lisbon_combined_lts2 |> st_drop_geometry()
# trips_lisbon_combined = trips_lisbon_combined_lts3 |> st_drop_geometry()

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

# for LTS2

trips_lisbon_diferences = trips_lisbon_combined |> 
  select(from_id, to_id, total_distance, year) |> 
  pivot_wider(values_from = total_distance, names_from = year, names_prefix = "distance_")

trips_lisbon_diferences = trips_lisbon_diferences |> 
  mutate(dif_1621 = distance_2021 - distance_2016,
         dif_2126 = distance_2026 - distance_2021) |> 
  arrange(dif_2126)


ggplot(trips_lisbon_diferences, aes(x = distance_2016, y = distance_2026)) +
  geom_point(alpha = 0.1, color = "midnightblue") +
  geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed") +
  geom_smooth(method = "lm", color = "green") +
  labs(title = "OD Distance: 2016 vs. 2026",
       subtitle = "Points below the red line represent improved routing efficiency",
       x = "Original Distance 2016 (m)",
       y = "Projected Distance 2026 (m)") +
  theme_minimal()

ggplot(trips_lisbon_diferences, aes(x = distance_2016, y = distance_2021)) +
  geom_point(alpha = 0.1, color = "midnightblue") +
  geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed") +
  geom_smooth(method = "lm", color = "green") +
  labs(title = "OD Distance: 2016 vs. 2021",
       subtitle = "Points below the red line represent improved routing efficiency",
       x = "Original Distance 2016 (m)",
       y = "Projected Distance 2021 (m)") +
  theme_minimal()
ggplot(trips_lisbon_diferences, aes(x = distance_2021, y = distance_2026)) +
  geom_point(alpha = 0.1, color = "midnightblue") +
  geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed") +
  geom_smooth(method = "lm", color = "green") +
  labs(title = "OD Distance: 2021 vs. 2026",
       subtitle = "Points below the red line represent improved routing efficiency",
       x = "Original Distance 2021 (m)",
       y = "Projected Distance 2026 (m)") +
  theme_minimal()

# What is the average distance reduction?
trips_lisbon_diferences |>
  mutate(change_pct = (distance_2021 - distance_2016) / distance_2016) |>
  summarise(avg_reduction = mean(change_pct, na.rm = TRUE) * 100)

# 2016 - 2026 : -5.37%
# 2021 - 2026 : -2.91%
# 2016 - 2021 : -2.26%

# 
# trips_lisbon_diferences |>
#   # Filter NAs and sort by the biggest gains
#   filter(!is.na(dif_2126)) |>
#   arrange(dif_2126) |>
#   mutate(cumulative_gain = cumsum(dif_2126) / 1000) |> # Convert to km
#   mutate(index = row_number()) |>
#   ggplot(aes(x = index, y = cumulative_gain)) +
#   geom_line(size = 1.2, color = "#2ecc71") +
#   labs(title = "Cumulative Infrastructure Efficiency (2021-2026)",
#        subtitle = "Total kilometers saved across all sampled OD pairs",
#        x = "Ranked OD Pairs (Highest Gain to Lowest)",
#        y = "Total Cumulative Distance Saved (km)") +
#   theme_minimal()


# Pivot data to compare the two periods easily
gains_long <- trips_lisbon_diferences |>
  select(dif_1621, dif_2126) |>
  pivot_longer(everything(), names_to = "period", values_to = "diff") |>
  mutate(period = recode(period, 
                         "dif_1621" = "2016 to 2021", 
                         "dif_2126" = "2021 to 2026"))

ggplot(gains_long, aes(x = diff, fill = period)) +
  geom_histogram(binwidth = 250, color = "white", alpha = 0.7, position = "identity") +
  geom_vline(xintercept = 0, linetype = "dashed", size = 1) +
  annotate("text", x = -2500, y = 1500, label = "Efficiency Gain\n(Shorter Trips)", color = "darkgreen") +
  annotate("text", x = 2500, y = 1500, label = "Efficiency Loss\n(Longer Trips)", color = "darkred") +
  scale_fill_manual(values = c("2016 to 2021" = "#3498db", "2021 to 2026" = "#e67e22")) +
  labs(title = "Distribution of Trip Distance Changes",
       subtitle = "Negative values indicate the new infrastructure allowed for shorter routes",
       x = "Change in Distance (meters)",
       y = "Number of OD Pairs") +
  theme_minimal() + 
  xlim(-3500, +3500) # Cutting off outliers for better visibility




# identify segments -------------------------------------------------------

# 1. Identify the OD pairs with the biggest distance savings (the 'Gains')
top_gains_ids <- trips_lisbon_diferences |>
  filter(dif_2126 < 0) |> # Only look at improvements
  slice_min(dif_2126, n = 1000) |> # Look at the top 1000 'improved' trips
  select(from_id, to_id)

# 2. Extract the geometries for these specific efficient trips from your 2026 results
efficient_geometries <- trips_lisbon_combined_lts2 |> 
  filter(year == 2026) |>
  inner_join(top_gains_ids, by = c("from_id", "to_id"))

# 3. Break the routes into individual segments and count usage
lisbon_ci_2026 = st_read("data/lisbon/lisbon_ci_osmactive_260101.gpkg")
infra_usage <- st_join(lisbon_ci_2026, efficient_geometries, join = st_intersects) |>
  group_by(osm_id) |> # infrastructure segment
  summarise(trip_count = n()) |>
  arrange(desc(trip_count))

# 4. View the Top 10 Segments
top_10_segments <- head(infra_usage, 10)
mapview(top_10_segments)
