# Install and load required packages
# install.packages("fixest")
library(fixest)
library(dplyr)

# Assuming your data is loaded into a dataframe called 'bike_data'
# Variables: route_id, city_id, year, circuity, lts_score, accessibility, 
# infra_protected_km, infra_painted_km

bike_data = read.csv("data/pipeline/final_city_estimations.csv")
city_discard = c("Lisbon", "Cairo", "Cape Town", "Munich", "Hong Kong") #Ljubliana? Amsterdam?
bike_data = bike_data |> filter(!city %in% city_discard)




# validation check --------------------------------------------------------

# Assuming your dataframe is called 'bike_data'
# Variables used: city_id, year, infra_protected_km

variation_check <- bike_data %>%
  # 1. Isolate the city-level infrastructure data 
  # (This drops the 20k routes and leaves just 135 rows: 45 cities x 3 years)
  distinct(city, year, total_ci_m) %>% 
  
  # 2. Group by city and sort by year to calculate changes over time
  group_by(city) %>%
  arrange(year) %>%
  
  # 3. Calculate baseline, total built, and percentage increase
  summarise(
    baseline_km = first(total_ci_m),
    final_km = last(total_ci_m),
    total_built_km = final_km - baseline_km,
    
    # Adding +1 to denominator to avoid division by zero if baseline was 0
    pct_increase = (total_built_km / (baseline_km + 0.1)) * 100 
  ) %>%
  arrange(desc(total_built_km)) # Sort to see the cities that built the most at the top

# View the results for individual cities
head(variation_check, 10)

# 4. The Moment of Truth: How many cities actually built new infrastructure?
summary_stats <- variation_check %>%
  summarise(
    cities_with_no_change = sum(total_built_km == 0),
    cities_with_growth = sum(total_built_km > 0),
    avg_km_built = mean(total_built_km)
  )

print(summary_stats)


# Elasticities ------------------------------------------------------------



# To get elasticities, we create log transformations. 
bike_data_model <- bike_data %>%
  filter(lts %in% c(1,2)) |> 
  mutate(
    log_circuity = log(avg_circuity),
    log_distance = log(avg_distance_m),
    lig_duration = log(avg_duration_min),
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
  mutate(lts_factor = factor(lts)) # not ordered!

# Model 1: Elasticity of Protected Infra on Circuity
# The | separates the main variables from the fixed effects
model_circuity_interacted <- feols(
  log_circuity ~ 
    log_ci_strong_km * lts_factor + 
    log_ci_medium_km * lts_factor + 
    log_ci_weak_km * lts_factor + 
    log_ci_foot_km * lts_factor
| city + year, 
data = bike_data_model, 
cluster = ~city) # Clustering standard errors at the city level

model_distance <- fepois(log_distance ~ ci_type_sep_m/1000 +
                          ci_type_paint_m/1000 +
                          ci_type_mixed_m/1000 +
                          ci_type_foot_m/1000
                        | city, 
                        data = bike_data, 
                        cluster = ~city) # Clustering standard errors at the city level

# View results
summary(model_circuity)
summary(model_circuity_interacted)
summary(model_distance)



# other approach ----------------------------------------------------------

# 1. Model Circuity split by LTS
models_circuity <- feols(
  log_circuity ~ log_ci_strong_km + log_ci_medium_km + log_ci_weak_km + log_ci_foot_km + log_total_road_km
  | city + year,
  data = bike_data_model,
  split = ~lts,           # This tells fixest to run 4 separate models!
  cluster = ~city
)

# 2. Model Distance split by LTS
models_distance <- feols(
  log_distance ~ log_ci_strong_km +
    log_ci_medium_km +
    log_ci_weak_km +
    # log_ci_foot_km +
    log_total_road_km
  # log_distance ~ log_total_ci_km  + log_total_road_km
  # | city + year,
  | city ,
  data = bike_data_model,
  split = ~ lts,
  cluster = ~ city
)

# Model Accessibility
models_access <- feols(
  log_access ~ log_ci_strong_km + log_ci_medium_km + log_ci_weak_km + log_ci_foot_km + log_total_road_km
  | city + year,
  data = bike_data_model,
  split = ~lts,
  cluster = ~city
)

# Model Safety (Proportion of LTS 1 on the route)
models_safety_lts1 <- feols(
  log_lts1 ~ log_ci_strong_km + log_ci_medium_km + log_ci_weak_km + log_ci_foot_km + log_total_road_km
  | city + year,
  data = bike_data_model,
  split = ~lts,
  cluster = ~city
)



# 3. Output beautiful comparison tables
# Each column will represent an LTS level (1, 2, 3, 4)
etable(models_circuity, dict = c(log_ci_strong_km = "Strong Infra", log_circuity = "Circuity"))
etable(models_distance)
etable(models_access)
etable(models_safety_lts1)

summary(models_circuity)


# Exporting to a CSV for Excel
etable(
  models_circuity,
  models_distance,
  models_safety_lts1,
  models_access,
  file = "infrastructure_elasticities.csv",
  replace = TRUE
)

