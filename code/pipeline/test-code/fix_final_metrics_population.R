library(tidyverse)
# read city list to get population
city_list <- read.csv("data/city_list.txt", header=FALSE) |>
  rename(city=V1, lat=V2, lon=V3, population=V4, country=V5, country_code=V6) |>
  select(city, population)

# read existing final estimations
final_df <- read.csv("data/pipeline/final_city_estimations.csv")

# remove existing population column
if ("population" %in% names(final_df)) {
  final_df <- final_df |> select(-population)
}

# correct city case for joining (e.g. sydney -> Sydney)
final_df <- final_df |> mutate(city = tools::toTitleCase(tolower(city)))

# join
final_df <- final_df |> left_join(city_list, by="city")

# reorder
final_df <- final_df |> select(city, year, lts, run_timestamp, population, everything())

# write back
write.csv(final_df, "data/pipeline/final_city_estimations.csv", row.names=FALSE)
cat("Population updated in final_city_estimations.csv\n")
