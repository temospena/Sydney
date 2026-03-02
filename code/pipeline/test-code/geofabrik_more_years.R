library(dplyr)

# Assuming your data is in a dataframe called 'df'
geofabrik_expanded <- geofabrik %>%
  # Create rows for year 19 using year 16 data
  bind_rows(
    geofabrik %>% filter(year == 16) %>% mutate(year = 19)
  ) %>%
  # Create rows for year 24 using year 21 data
  bind_rows(
    geofabrik %>% filter(year == 21) %>% mutate(year = 24)
  ) %>%
  # Sort the results by city and year
  arrange(city, year)

# View the result
head(geofabrik_expanded, 10)

write_csv(geofabrik_expanded, "data/geofabrik_regions.csv")

geofabric_update = geofabrik_expanded |> group_by(city, geofabrik_region) |>  summarise(count = n()) |> filter(count <5)