# Load required packages
library(dplyr)
library(ggplot2)

final_city_estimations <- read_csv("data/pipeline/final_city_estimations.csv")

unique(final_city_estimations$city)
length(unique(final_city_estimations$city)) - 5 #cairo, cape town, lisbon, munich, hong kong

summary(final_city_estimations$processing_time_minutes[final_city_estimations$processing_time_minutes > 10], na.rm = TRUE)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max.    NA's 
#   10.53   15.29   18.17   19.64   22.67   37.81     204 
summary(final_city_estimations$total_ci_m)
# Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
# 0  179087  280806  302886  398848  838957 

# 1. Prepare the data
plot_data <- final_city_estimations %>%
  filter(lts %in% c(1,2)) |> 
  # Group by city and year to handle the multiple LTS rows
  group_by(city, year) %>%
  # Take the first value of total_ci_m (or max/mean, since it's likely duplicated) 
  # and convert meters to kilometers
  summarise(total_ci_km = max(total_ci_m, na.rm = TRUE) / 1000, .groups = "drop")

plot_data_wide = plot_data |> 
  pivot_wider(id_cols= city, names_from = year, values_from=total_ci_km)

# 2. Create the plot
ggplot(plot_data, aes(x = year, y = total_ci_km, color = city, group = city)) +
  geom_line(linewidth = 1) +      # Draw the trend lines
  geom_point(size = 2.5) +        # Add markers for the specific years
  geom_text(
    data = plot_data %>% filter(year == 2026), # Only label the 2026 points
    aes(label = city), 
    hjust = 0,         # Left-align the text so it starts directly at the point
    nudge_x = 0.3,     # Push the text slightly to the right so it doesn't overlap the dot
    size = 4         
    # fontface = "bold"
  ) +
  # Force the X-axis to only show the specific years in your dataset
  scale_x_continuous(breaks = c(2016, 2019, 2021, 2024, 2026),
                     limits = c(2016, 2027)) + 
  theme_minimal() +
  labs(
    title = "Evolution of Total Cycling Infrastructure by City",
    subtitle = "Comparing infrastructure growth from 2016 to 2026",
    x = "Year",
    y = "Total Infrastructure (km)",
    color = "City"
  ) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    panel.grid.minor.x = element_blank(), # Keep the background clean
    legend.position = "none" # You can change this to "bottom" if you have many cities
  ) 
