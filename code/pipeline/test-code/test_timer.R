library(dplyr)
csv_path <- "data/pipeline/final_city_estimations.csv"
city_name <- "Austin"
current_timestamp <- "20260226_151115"
duration_mins <- 12.34

df <- read.csv(csv_path)
str(df$city)
str(df$run_timestamp)
str(df$processing_time_minutes)

# Update only the rows from the current run
df <- df %>%
  mutate(processing_time_minutes = if_else(
    city == city_name & run_timestamp == current_timestamp,
    round(duration_mins, 2),
    as.numeric(processing_time_minutes)
  ))

res <- df %>% filter(city == city_name & run_timestamp == current_timestamp)
print(res$processing_time_minutes)
