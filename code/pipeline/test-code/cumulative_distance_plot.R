library(ggplot2)
library(scales) # for percentage labels

ggplot(sydney_routing_stats_all, aes(x = total_distance/100)) +
  # This calculates the cumulative % automatically
  stat_ecdf(geom = "line", color = "firebrick", size = 1) +
  # Optional: Add points to see the individual trip markers
  # stat_ecdf(geom = "point") + 
  scale_y_continuous(labels = percent) +
  labs(
    title = "Cumulative Distribution of Trip Distances",
    x = "Trip Distance (km)",
    y = "% of Total Trips"
  ) +
  theme_minimal()