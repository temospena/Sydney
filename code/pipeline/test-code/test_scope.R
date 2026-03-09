library(dplyr)
df <- data.frame(city = "Austin", run_timestamp = "123", processing_time_minutes = NA)
city_name <- "Austin"
current_timestamp <- "123"
duration_mins <- 10.5

update_df <- function() {
  df |> mutate(processing_time_minutes = if_else(
    city == city_name & run_timestamp == current_timestamp,
    round(duration_mins, 2),
    as.numeric(processing_time_minutes)
  ))
}

print(update_df())
