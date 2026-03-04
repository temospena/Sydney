# model test for route levels
library(dplyr)
library(fixest)


# load data ---------------------------------------------------------------

final_estimations = read.csv("data/pipeline/final_city_estimations.csv")
# dput(unique(final_estimations$city))

target_cities = c(
  "Amsterdam", "Austin", "Barcelona", "Beijing", "Berlin", "Bogota", 
  "Bologna", "Brussels", "Buenos Aires", "Cairo", "Cape Town", 
  "Chicago", "Christchurch", "Curitiba", "Dublin", "Gent", "Glasgow", 
  "Graz", "Hamburg", "Helsinki", "Hong Kong", "Kyoto", "Leeds", 
  "Lisbon", "Ljubljana", "London", "Lyon", "Madrid", "Melbourne", 
  "Mexico City", "Milan", "Minneapolis", "Montpellier", "Montréal", 
  "Munich", "Nantes", "New York", "Oslo", "Paris", "Portland", 
  "San Francisco", "Santiago", "Sao Paulo", "Seattle", "Seoul", 
  "Seville", "Shanghai", "Stockholm", "Strasbourg", "Sydney", "Taipei", 
  "Tokyo", "Turin", "Vancouver", "Vienna", "Warsaw", "Zurich"
  )
cities_less_100k = c("Cairo", "Cape Town", "Hong Kong")
cities_weired_tagging = c("Lisbon", "Munich", "Ljubljana") # Strasbourg, Vancouver
cities_no_data = c()
cities_no_10pct_growth = c("Amsterdam",  "Stockhoml")
target_cities_clean = setdiff(target_cities,
                              c(cities_less_100k,
                                cities_weired_tagging,
                                cities_no_data,
                                cities_no_10pct_growth)) #50

## at city level
city_data_model <- final_estimations |> 
  filter(city %in% target_cities_clean) |> 
  mutate(city = tolower(city)) |> 
  filter(lts %in% c(1,2)) |> 
  mutate(
    log_circuity = log(avg_circuity),
    log_distance = log(avg_distance_m),
    log_duration = log(avg_duration_min),
    log_lts1 = log(pct_lts1 + 1), # Adding a small constant to avoid log(0)
    log_lts2 = log(pct_lts2 + 1),
    log_lts3 = log(pct_lts3 + 1),
    log_lts4 = log(pct_lts4 + 1),
    log_access = log(access_15min_vol),
    log_ci_route_pct = log(pct_ci_route + 1),
    log_ci_strong_km = log(ci_type_sep_m/1000 + 1),
    log_ci_medium_km = log(ci_type_paint_m/1000 + 1),
    log_ci_weak_km = log(ci_type_mixed_m/1000 + 1),
    log_ci_foot_km = log(ci_type_foot_m/1000 + 1),
    log_total_road_km = log(total_road_m/1000 + 1),
    log_total_ci_km = log(total_ci_m/1000 + 1)
  ) |> 
  mutate(
    ci_city_strong_km = ci_type_sep_m / 1000,
    ci_city_medium_km = ci_type_paint_m / 1000,
    ci_city_weak_km   = ci_type_mixed_m / 1000,
    ci_city_foot_km   = ci_type_foot_m / 1000
  ) |> 
  mutate(lts_factor = factor(lts))




## at route level
routing_stats_all = data.frame() # initialize
routing_stats_model = data.frame()

for (city in target_cities_clean) {
  print(paste("Processing", city))
  
  city = tolower(city)
  # Here you would load and process the routing stats for each city
  # For example:
  routing_stats_city = readRDS(paste0("data/pipeline/", city, "/", city, "_routing_stats_all.rds"))
  routing_stats_city = routing_stats_city |> 
    mutate(city = city,
           year = as.integer(paste0("20", year)))
  
  routing_stats_all = rbind(routing_stats_all, routing_stats_city)
}
rm(routing_stats_city) # clean up

routing_stats_model = routing_stats_all |> 
  filter(lts %in% c(1,2)) |> # only lts 1 and 2
  mutate(
    route_id = paste(city, from_id, to_id, sep = "_"),
    circuity = total_distance / euclidean_distance,
    ci_strong_km = route_ci_strong_m / 1000,
    ci_medium_km = route_ci_medium_m / 1000,
    ci_weak_km   = route_ci_weak_m / 1000,
    ci_foot_km   = route_ci_foot_m / 1000,
    # ci_km = (route_ci_strong_m + route_ci_medium_m + route_ci_weak_m + route_ci_foot_m)/1000,
    # log_total_road_km 

    route_avg_lts = (1 * route_pct_lts1 +
                       2 * route_pct_lts2 + 
                       3 * route_pct_lts3 +
                       4 * route_pct_lts4) / 100,     # Weighted Average LTS (Scale 1.0 to 4.0)
    route_pct_safe = route_pct_lts1 + route_pct_lts2 # Total "Safe" Percentage (LTS 1 + LTS 2)
  ) |>
  filter(circuity >= 1 & !is.na(total_duration)) |>  # clean wered results
  mutate(log_access = log(access_15min_vol+1)) # log

nrow(routing_stats_model) # 10 million routes across 51 cities
# str(routing_stats_all)

# check the percentage of zeros in access_15min_vol
# sum(routing_stats_model$access_15min_vol == 0) / nrow(routing_stats_model) 


# for accessibility
access_stats_model <- routing_stats_model |>
  # # Collapse the route data down to just the unique Origins (from_id)
  # distinct(city, from_id, year, lts, access_15min_vol) |>

  # We join by both 'city' and 'year' so the network size matches the specific year.
  left_join(
    city_data_model |> select(city, year, total_road_m, total_ci_m) |> distinct(), 
    by = c("city", "year")
  ) |>
  mutate(log_access = log(access_15min_vol + 1),
         total_ci_km = total_ci_m / 1000,
         log_total_road_km = log(total_road_m / 1000)
         )



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
  route_avg_lts ~ ci_strong_km + ci_medium_km + ci_weak_km + ci_foot_km 
  | route_id + year,
  data = routing_stats_model,
  split = ~lts,
  cluster = ~city 
)

# Model B: Does infrastructure increase the 'Safe' portion of the trip? (Level-Level)
model_route_safe_pct <- feols(
  route_pct_safe ~ ci_strong_km + ci_medium_km + ci_weak_km + ci_foot_km 
  | route_id + city,
  data = routing_stats_model,
  split = ~lts,
  cluster = ~city
)

# # 4. Model Interruptions (Log-Linear)
# # Does closing gaps on THIS route reduce the number of times they are dumped into traffic?
# model_route_interrupt <- feols(
#   log(route_interruptions_count + 1) ~ ci_strong_km + ci_medium_km + ci_weak_km + ci_foot_km
#   | route_id + year,
#   data = routing_stats_model,
#   split = ~lts,
#   cluster = ~city
# )

# Model accessibility
model_origin_access <- feols(
  log_access ~ log(total_ci_km+1) + log_total_road_km 
  | route_id + year,
  data = access_stats_model,
  split = ~lts,
  cluster = ~city
)


# View the results
etable(model_route_duration, dict = c("ci_strong_km" = "Protected CI (km)", "ci_medium_km" = "Painted CI (km)"))
etable(model_route_circuity, dict = c("ci_strong_km" = "Protected CI (km)", "ci_medium_km" = "Painted CI (km)"))
# this is the most exciting:
etable(model_route_safety, dict = c("ci_strong_km" = "Protected CI (km)", "ci_medium_km" = "Painted CI (km)"))
# etable(model_route_interrupt, dict = c("ci_strong_km" = "Protected CI (km)", "ci_medium_km" = "Painted CI (km)"))
etable(model_route_avg_lts, model_route_safe_pct, dict = c("ci_strong_km" = "Protected CI (km)", "ci_medium_km" = "Painted CI (km)"))
etable(model_origin_access, dict = c("total_ci_km" = "Total City CI Built (km)"))

# fixed effects
summary(fixef(model_route_safety[[1]])) #only for lts1
# plot(fixef(model_route_safety[[1]]))

# errors




coefplot(model_route_duration)
coefplot(model_route_safety)





# try form zero -----------------------------------------------------------

library(dplyr)
library(fixest)
library(modelsummary) # For exporting beautiful tables for your paper

# ==========================================
# STEP 1: FILTER TO YOUR TARGET DEMOGRAPHIC
# ==========================================
# We only care about LTS 1 (cautious riders) for now.
city_lts1 <- city_data_model |>
  filter(lts == 1) |> 
  mutate(total_ci_km = total_ci_m /100)
route_lts1 <- routing_stats_model |>
  filter(lts == 1) |> 
  mutate(
    dist_cat = case_when(
      euclidean_distance < 2000 ~ "1_Short (<2km)",
      euclidean_distance >= 2000 & euclidean_distance < 5000 ~ "2_Medium (2-5km)",
      euclidean_distance >= 5000 ~ "3_Long (>5km)"
    )
  )

# ==========================================
# STEP 2: THE MACRO STORY (CITY LEVEL)
# Does a 1% bigger network mean 1% more accessibility?
# ==========================================
macro_access <- feols(
  log_access ~ log_total_ci_km + log_total_road_km | city + year,
  data = city_lts1
)

# ==========================================
# STEP 3: THE MICRO STORY (ROUTE LEVEL)
# Does 1km of new infrastructure change the specific trip?
# ==========================================
# 1. Trip Duration (Does it make the trip faster?)
micro_duration <- feols(
  log(total_duration) ~ ci_strong_km + ci_medium_km + ci_weak_km
  + ci_foot_km
   | route_id + year,
  data = route_lts1,
  cluster = ~city 
)

# 2. Trip Circuity (Does it make the route more direct?)
micro_circuity <- feols(
  log(circuity) ~ ci_strong_km + ci_medium_km  + ci_weak_km
  + ci_foot_km
  | route_id + year,
  data = route_lts1,
  cluster = ~city
)

# 3. Trip Safety (Does it increase the completely safe portion of the ride?)
micro_safety <- feols(
  route_pct_safe ~ ci_strong_km + ci_medium_km  + ci_weak_km
  # + ci_foot_km
  | route_id + year,
  data = route_lts1,
  cluster = ~city
)

# ==========================================
# STEP 4: PREPARE THE RESULTS FOR YOUR PAPER
# ==========================================
# Micro models
modelsummary(
  list("Log Duration" = micro_duration, 
       "Log Circuity" = micro_circuity, 
       "% Safe Route" = micro_safety),
  coef_rename = c("ci_strong_km" = "Protected cycling infra (added km)", 
                  "ci_medium_km" = "Painted lane (added km)",
                  "ci_weak_km" = "Sharrow type (added km)",
                  "ci_foot_km" = "Shared with pedestrians (added km)"),
  stars = TRUE,
  title = "Impact of 1km Infrastructure Expansion on Route Characteristics (LTS 1)",
  gof_omit = "IC|Log.Lik|F" # |RMSE ; Cleans up the bottom of the table
)

# Macro model
modelsummary(
  list("Log 15-Min Accessibility (buildings)" = macro_access),
  coef_rename = c("log_total_ci_km" = "Total City CI (Log)",
                  "log_total_road_km" = "Total City Road Network (Log)"),
  stars = TRUE,
  title = "Macro Impact of Network Expansion on City-Wide Accessibility (LTS 1)",
  gof_omit = "IC|Log.Lik|F" #|RMSE
)



# other interactions ------------------------------------------------------

# Distance bins interaction
# We use fixest's i() function to interact a categorical variable with a continuous one.
# Setting ref = "3_Long (>7km)" means the baseline coefficient represents Long trips,
# and the other coefficients will show the *additional* impact for Short/Medium trips.
micro_duration_dist <- feols(
  log(total_duration) ~ i(dist_cat, ci_strong_km, ref = "3_Long (>5km)") + 
    i(dist_cat, ci_medium_km, ref = "3_Long (>5km)") | route_id + year,
  data = route_lts1,
  cluster = ~city
)

etable(micro_duration_dist)
#If that interaction term is negative and significant, you have mathematically
# proven that infrastructure has a compounded, disproportionate benefit for short, local trips.



# The Macro Quadratic Model
# We use I(total_ci_km^2) to test if the benefit of infrastructure accelerates as the network grows.
macro_access_quad <- feols(
  log_access ~ total_ci_km + I(total_ci_km^2) + log_total_road_km
  | city + year,
  data = city_lts1
)

etable(macro_access_quad)
