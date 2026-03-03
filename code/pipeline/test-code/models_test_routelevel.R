# model test for routlevels

target_cities = c(
"Amsterdam", "Austin", "Beijing", "Berlin", "Bogota", # Barcelona
"Bologna", "Brussels", "Buenos Aires",
"Sydney", "Paris", "Barcelona", "New York", "Lisbon")

routing_stats_all = data.frame() # initialize

for (city in target_cities) {
  print(paste("Processing", city))
  
  city = tolower(city)
  # Here you would load and process the routing stats for each city
  # For example:
  routing_stats_city = readRDS(paste0("data/pipeline/", city, "/", city, "_routing_stats_all.rds"))
  routing_stats_city = routing_stats_city |> 
    mutate(city = city)
  
  routing_stats_all = rbind(routing_stats_all, routing_stats_city)
}
rm(routing_stats_city) # clean up

routing_stats_model = routing_stats_all |> 
  filter(lts %in% c(1,2)) |> 
  mutate(
    route_id = paste(city, from_id, to_id, sep = "_"),
    circuity = total_distance / euclidean_distance,
    ci_strong_km = route_ci_strong_m / 1000,
    ci_medium_km = route_ci_medium_m / 1000,
    ci_weak_km   = route_ci_weak_m / 1000,
    ci_foot_km   = route_ci_foot_m / 1000,

    route_avg_lts = (1 * route_pct_lts1 +
                       2 * route_pct_lts2 + 
                       3 * route_pct_lts3 +
                       4 * route_pct_lts4) / 100,     # Weighted Average LTS (Scale 1.0 to 4.0)
    route_pct_safe = route_pct_lts1 + route_pct_lts2 # Total "Safe" Percentage (LTS 1 + LTS 2)
  ) |>
  filter(circuity >= 1 & !is.na(total_duration)) # clean wered results

# str(routing_stats_all)

# check the percentage of zeros in access_15min_vol
sum(routing_stats_model$access_15min_vol == 0) / nrow(routing_stats_model) # 74% !!!

# models ------------------------------------------------------------------


# 1. Model Duration (Log-Linear)
# Does dropping 1km of infrastructure ON THIS ROUTE make it faster?
model_route_duration <- feols(
  log(total_duration) ~ ci_strong_km + ci_medium_km + ci_weak_km + ci_foot_km
  | route_id + year,
  data = routing_stats_model,
  split = ~lts,
  cluster = ~city # Clustering standard errors at the city level
)

# 2. Model Circuity (Log-Linear)
# Does infrastructure allow this specific route to take a more direct path / shorter somehow?
model_route_circuity <- feols(
  log(circuity) ~ ci_strong_km + ci_medium_km + ci_weak_km + ci_foot_km
  | route_id + year,
  data = routing_stats_model,
  split = ~lts,
  cluster = ~city
)

# 3. Model Safety (Level-Level)
# Does infrastructure directly increase the percentage of this trip spent in low-stress conditions?
# Note: route_pct_lts1 is already a percentage (0-100), so no need to log it.
model_route_safety <- feols(
  route_pct_lts1 ~ ci_strong_km + ci_medium_km + ci_weak_km + ci_foot_km
  | route_id + year,
  data = routing_stats_model,
  split = ~lts,
  cluster = ~city
)


## Safety composite
# Model A: Does infrastructure lower the average stress score? (Level-Level)
model_route_avg_lts <- feols(
  route_avg_lts ~ ci_strong_km + ci_medium_km + ci_weak_km + ci_foot_km | route_id + year,
  data = routing_stats_model,
  split = ~lts,
  cluster = ~city 
)

# Model B: Does infrastructure increase the 'Safe' portion of the trip? (Level-Level)
model_route_safe_pct <- feols(
  route_pct_safe ~ ci_strong_km + ci_medium_km + ci_weak_km + ci_foot_km | route_id + year,
  data = routing_stats_model,
  split = ~lts,
  cluster = ~city
)

# 4. Model Interruptions (Log-Linear)
# Does closing gaps on THIS route reduce the number of times they are dumped into traffic?
model_route_interrupt <- feols(
  log(route_interruptions_count + 1) ~ ci_strong_km + ci_medium_km + ci_weak_km + ci_foot_km
  | route_id + year,
  data = routing_stats_model,
  split = ~lts,
  cluster = ~city
)

# View the results
etable(model_route_duration, dict = c("ci_strong_km" = "Protected CI (km)", "ci_medium_km" = "Painted CI (km)"))
etable(model_route_circuity, dict = c("ci_strong_km" = "Protected CI (km)", "ci_medium_km" = "Painted CI (km)"))
etable(model_route_safety, dict = c("ci_strong_km" = "Protected CI (km)", "ci_medium_km" = "Painted CI (km)"))
etable(model_route_interrupt, dict = c("ci_strong_km" = "Protected CI (km)", "ci_medium_km" = "Painted CI (km)"))
etable(model_route_avg_lts, model_route_safe_pct, dict = c("ci_strong_km" = "Protected CI (km)", "ci_medium_km" = "Painted CI (km)"))
