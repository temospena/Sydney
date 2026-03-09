# Install and load required packages
# install.packages("fixest")
library(fixest)
library(dplyr)

# Assuming your data is loaded into a dataframe called 'bike_data'
# Variables: route_id, city_id, year, circuity, lts_score, accessibility, 
# infra_protected_km, infra_painted_km

bike_data = read.csv("data/pipeline/final_city_estimations.csv")
city_discard = c("Lisbon", "Cairo", "Cape Town", "Munich", "Hong Kong", "Amsterdam", "Stockhoml") # less than 100k, less than 10% growth
bike_data = bike_data |> filter(!city %in% city_discard)




# validation check --------------------------------------------------------

# Assuming your dataframe is called 'bike_data'
# Variables used: city_id, year, infra_protected_km

variation_check <- bike_data |>
  # 1. Isolate the city-level infrastructure data 
  # (This drops the 20k routes and leaves just 135 rows: 45 cities x 3 years)
  distinct(city, year, total_ci_m) |> 
  
  # 2. Group by city and sort by year to calculate changes over time
  group_by(city) |>
  arrange(year) |>
  
  # 3. Calculate baseline, total built, and percentage increase
  summarise(
    baseline_km = first(total_ci_m/1000),
    final_km = last(total_ci_m/1000),
    total_built_km = final_km - baseline_km,
    
    # Adding +1 to denominator to avoid division by zero if baseline was 0
    pct_increase = (total_built_km / (baseline_km + 0.1)) * 100 
  ) |>
  arrange(desc(total_built_km)) # Sort to see the cities that built the most at the top

# View the results for individual cities
head(variation_check, 10)

# 4. The Moment of Truth: How many cities actually built new infrastructure?
summary_stats <- variation_check |>
  summarise(
    cities_with_no_change = sum(total_built_km == 0),
    cities_with_growth = sum(total_built_km > 0),
    avg_km_built = mean(total_built_km)
  )

print(summary_stats)


# Elasticities ------------------------------------------------------------



# To get elasticities, we create log transformations. 
bike_data_model <- bike_data |>
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
    ci_strong_km = ci_type_sep_m / 1000,
    ci_medium_km = ci_type_paint_m / 1000,
    ci_weak_km   = ci_type_mixed_m / 1000,
    ci_foot_km   = ci_type_foot_m / 1000
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

# 2. Model trip duration split by LTS
models_duration <- feols(
  # log_duration ~ 
  #   log_ci_strong_km +
  #   log_ci_medium_km +
  #   log_ci_weak_km +
  #   log_ci_foot_km +
  #   log_total_road_km
  log_duration ~ log_total_ci_km  + log_total_road_km
  | city + year,
  # | city,
  data = bike_data_model,
  split = ~ lts,
  cluster = ~ city
)

# Model Accessibility
models_access <- feols(
  # log_access ~ log_ci_strong_km + log_ci_medium_km + log_ci_weak_km + log_ci_foot_km + log_total_road_km
  log_access ~ log_total_ci_km  + log_total_road_km
  | city + year,
  data = bike_data_model,
  split = ~lts,
  cluster = ~city
)

# Model Safety (Proportion of LTS 1 on the route)
models_safety_lts1 <- feols(
  # log_lts1 ~ log_ci_strong_km + log_ci_medium_km + log_ci_weak_km + log_ci_foot_km + log_total_road_km
  log_lts1 ~ log_total_ci_km  + log_total_road_km
  | city + year,
  data = bike_data_model,
  split = ~lts,
  cluster = ~city
)


# 1. Did the infrastructure make impossible trips possible?
models_found_routes <- feols(
  log(found_routes) ~ log_total_ci_km + log_total_road_km
  | city + year,
  data = bike_data_model,
  split = ~lts,
  cluster = ~city
)

# 2. Did the infrastructure eliminate terrifying gaps in the network?
# (Adding +1 inside the log just in case some cities achieved 0 interruptions)
models_interruptions <- feols(
  log(avg_ci_interruptions + 1) ~
    # log_total_ci_km + log_total_road_km 
    # log_ci_strong_km + log_ci_medium_km + log_ci_weak_km + log_ci_foot_km + log_total_road_km # log-log
  ci_strong_km + ci_medium_km + ci_weak_km + ci_foot_km + log_total_road_km # log-linear
  | city + year,
  data = bike_data_model,
  split = ~lts,
  cluster = ~city
)



## Results
# Each column will represent an LTS level (1, 2, 3, 4)
etable(models_circuity, dict = c(log_ci_strong_km = "Strong Infra", log_circuity = "Circuity"))
etable(models_distance)
etable(models_duration)
etable(models_access)
etable(models_safety_lts1)
etable(models_found_routes, dict = c("log_total_ci_km" = "Total Bike Infra"))
etable(models_interruptions, dict = c("log_total_ci_km" = "Total Bike Infra"))

summary(models_circuity)

bike_data_model |> filter(lts == 1) |> pull(avg_duration_min) |> summary()
# only reduces average duration from 27.50 to 27.48 minutes (about 1 second), which is a small change. 




# Exporting to a CSV for Excel
etable(
  models_circuity,
  models_distance,
  models_safety_lts1,
  models_access,
  file = "infrastructure_elasticities.csv",
  replace = TRUE
)




# plots -------------------------------------------------------------------

library(ggplot2)
library(tibble)

# 1. Create a function to extract coefficients and confidence intervals from your split models
extract_plot_data <- function(model_list, outcome_name) {
  
  # Create an empty dataframe to hold our results
  results <- data.frame()
  
  # Loop through each LTS model (1 to 4)
  for (i in 1:length(model_list)) {
    # Extract the coefficient table from the fixest model
    coef_table <- coeftable(model_list[[i]])
    
    # Define which variables we want to plot
    vars_to_plot <- c("log_ci_strong_km", "log_ci_medium_km", "log_ci_weak_km")
    
    for (var in vars_to_plot) {
      if (var %in% rownames(coef_table)) {
        est <- coef_table[var, "Estimate"]
        se <- coef_table[var, "Std. Error"]
        
        # Calculate 95% Confidence Intervals (Estimate +/- 1.96 * Standard Error)
        results <- rbind(results, data.frame(
          LTS_Level = paste("LTS", i),
          Variable = var,
          Estimate = est,
          Conf_Low = est - (1.96 * se),
          Conf_High = est + (1.96 * se),
          Outcome = outcome_name
        ))
      }
    }
  }
  return(results)
}

# 2. Extract the data from your specific model (assuming you ran models_interruptions_disagg)
# (If you want to plot accessibility instead, just swap the variable name here)
plot_data <- extract_plot_data(models_interruptions, "Network Interruptions")

# 3. Clean up the variable names so they look professional on the chart
plot_data <- plot_data |>
  mutate(
    Infra_Type = case_when(
      Variable == "log_ci_strong_km" ~ "1. Strong (Protected)",
      Variable == "log_ci_medium_km" ~ "2. Medium (Painted)",
      Variable == "log_ci_weak_km"   ~ "3. Weak (Mixed/Sharrows)"
    )
  )

# 4. Filter to just LTS 1 and LTS 2 (The target demographics for these policies)
plot_data_filtered <- plot_data |> filter(LTS_Level %in% c("LTS 1", "LTS 2"))

# 5. Build the ggplot!
forest_plot <- ggplot(plot_data_filtered, aes(x = Estimate, y = Infra_Type, color = LTS_Level)) +
  
  # Add the 'Zero Effect' vertical line
  geom_vline(xintercept = 0, linetype = "dashed", color = "darkgray", linewidth = 1) +
  
  # Add the confidence interval bars
  geom_errorbar(aes(xmin = Conf_Low, xmax = Conf_High), 
                position = position_dodge(width = 0.5), 
                width = 0.2, linewidth = 1) +
  
  # Add the point estimate dots
  geom_point(position = position_dodge(width = 0.5), size = 4) +
  
  # Customize colors (Blue for LTS 1, Orange for LTS 2)
  scale_color_manual(values = c("LTS 1" = "#1f77b4", "LTS 2" = "#ff7f0e")) +
  
  # Clean up the theme and labels
  theme_minimal(base_size = 14) +
  labs(
    title = "The 'Island of Safety' Effect",
    subtitle = "Impact of 1% Infrastructure Expansion on Route Interruptions (Gaps)",
    x = "Elasticity (Coefficient)",
    y = "",
    color = "Rider Tolerance"
  ) +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold")
  )

# Display the plot
print(forest_plot)

# 6. Save it as a high-res image for your report
# ggsave("interruptions_forest_plot.png", plot = forest_plot, width = 8, height = 5, dpi = 300)



### WIth log-linear
extract_plot_data_1km <- function(model_list, outcome_name) {
  results <- data.frame()
  
  for (i in 1:length(model_list)) {
    coef_table <- coeftable(model_list[[i]])
    
    # Notice we are calling the new UNLOGGED variable names here
    vars_to_plot <- c("ci_strong_km", "ci_medium_km", "ci_weak_km", "ci_foot_km")
    
    for (var in vars_to_plot) {
      if (var %in% rownames(coef_table)) {
        est <- coef_table[var, "Estimate"]
        se <- coef_table[var, "Std. Error"]
        
        # Calculate raw Confidence Intervals first
        raw_low <- est - (1.96 * se)
        raw_high <- est + (1.96 * se)
        
        # APPLY THE EXACT MATH: Convert to Percentage Change per 1km
        pct_est <- (exp(est) - 1) * 100
        pct_low <- (exp(raw_low) - 1) * 100
        pct_high <- (exp(raw_high) - 1) * 100
        
        results <- rbind(results, data.frame(
          LTS_Level = paste("LTS", i),
          Variable = var,
          Estimate_Pct = pct_est,
          Conf_Low_Pct = pct_low,
          Conf_High_Pct = pct_high,
          Outcome = outcome_name
        ))
      }
    }
  }
  return(results)
}

# Run the function on your new 1km model
plot_data_1km <- extract_plot_data_1km(models_interruptions, "Network Interruptions")

# Clean up names for the chart
plot_data_1km <- plot_data_1km |>
  mutate(
    Infra_Type = case_when(
      Variable == "ci_strong_km" ~ "1. Strong (Protected)",
      Variable == "ci_medium_km" ~ "2. Medium (Painted lanes)",
      Variable == "ci_weak_km"   ~ "3. Weak (Mixed morotized/Sharrows)",
      Variable == "ci_foot_km"  ~ "4. Foot (Pedestrian infra"
    )
  ) |> filter(LTS_Level %in% c("LTS 1", "LTS 2"))

# Build the chart!
ggplot(plot_data_1km, aes(x = Estimate_Pct, y = Infra_Type, color = LTS_Level)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "darkgray", linewidth = 1) +
  geom_errorbar(aes(xmin = Conf_Low_Pct, xmax = Conf_High_Pct), 
                position = position_dodge(width = 0.5), width = 0.2, linewidth = 1) +
  geom_point(position = position_dodge(width = 0.5), size = 4) +
  scale_color_manual(values = c("LTS 1" = "#1f77b4", "LTS 2" = "#ff7f0e")) +
  theme_minimal(base_size = 14) +
  labs(
    title = "Impact per Kilometer Built",
    subtitle = "Percentage change in route interruptions per 1 km of new infrastructure",
    x = "Percentage Change (%) per 1km Built",
    y = "",
    color = "Rider Tolerance"
  ) +
  theme(legend.position = "bottom", plot.title = element_text(face = "bold"))
