# model test for route levels
library(readr)
library(dplyr)
library(fixest)
library(modelsummary)


# load and prep data for modeling ---------------------------------------------------------------

final_estimations = read_csv("data/pipeline/final_city_estimations.csv")
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
                                cities_no_10pct_growth))
length(target_cities_clean) #50

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
  mutate(log_access = log(access_15min_vol+1), # log
         log_duration = log(total_duration+1)) |> 
  mutate(
    dist_cat = case_when(
      total_distance < 2000 ~ "1_Short (<2km)",
      total_distance >= 2000 & total_distance < 5000 ~ "2_Medium (2-5km)",
      total_distance >= 5000 & total_distance < 8000 ~ "3_Long (5-8km)",
      total_distance >= 8000 ~ "4_VeryLong (>8km)"
    ))

nrow(routing_stats_model) # 9.9 million routes across 51 cities
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





# fixed vs random effects -------------------------------------------------

library(plm)
# try a simple test log-linear
fixed = plm(log_circuity ~ total_ci_km, data= city_lts1, index = c("city", "year"), model = "within") 
random = plm(log_circuity ~ total_ci_km, data= city_lts1, index = c("city", "year"), model = "random") 
phtest(fixed,random) #Hausman test
#p-value = 1.791e-05, for FE city + year so we cannot reject the null hypothesis (the preferred model is random effects )
# p-value = 0.00011, for not FE year.
rm(fixed, random)

# USE THESE ONES!!! -----------------------------------------------------------

library(dplyr)
library(fixest)
library(modelsummary) # For exporting tables 

# ==========================================
# STEP 1: FILTER TO YOUR TARGET DEMOGRAPHIC
# ==========================================
# We only care about LTS 1 (cautious riders) for now.
city_lts1 <- city_data_model |>
  filter(lts == 1) |> 
  mutate(total_ci_km = total_ci_m /100)
route_lts1 <- routing_stats_model |>
  filter(lts == 1)

# also lts2 for sake of verification
city_lts2 <- city_data_model |>
  filter(lts == 2) |> 
  mutate(total_ci_km = total_ci_m /100)
route_lts2 <- routing_stats_model |>
  filter(lts == 2) 

# ==========================================
# STEP 2: THE MACRO STORY (CITY LEVEL)
# ==========================================

# 1. Average Duration (Log-Log)
macro_duration <- feols(
  log(avg_duration_min) ~ log_total_ci_km + log_total_road_km
  | city + year,
  # | city,
  data = city_lts1,
  # data = city_lts2,
  cluster = ~city # Cluster standard errors by city
)

# # 2. Average Circuity (Log-Log)
# macro_circuity <- feols(
#   log(avg_circuity) ~ log_total_ci_km + log_total_road_km | city + year,
#   data = city_lts1,
#   cluster = ~city
# )
# 
# # 3. Average Safety / LTS 1 (Level-Log)
# # Note: pct_lts1 is already a percentage (0-100), so no need to log the dependent variable.
# macro_safety <- feols(
#   pct_lts1 ~ log_total_ci_km + log_total_road_km | city + year,
#   data = city_lts1,
#   cluster = ~city
# )

# 4. Total Accessibility (Log-Log)
# Does building total city infrastructure lower the AVERAGE city trip duration?
macro_access <- feols(
  log_access ~ log_total_ci_km + log_total_road_km
  | city + year,
  # | city,
  data = city_lts1,
  # data = city_lts2,
  cluster = ~city
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
  # | route_id + city^year, # interaction
  # | route_id,
  data = route_lts1,
  # data = route_lts2,
  cluster = ~city 
)

# 2. Trip Circuity (Does it make the route more direct?)
micro_circuity <- feols(
  log(circuity) ~ ci_strong_km + ci_medium_km  + ci_weak_km
  + ci_foot_km
  | route_id + year,
  # | route_id,
  data = route_lts1,
  # data = route_lts2,
  cluster = ~city
)

# 3. Trip Safety (Does it increase the completely safe portion of the ride?)
micro_safety <- feols(
  route_pct_safe ~ ci_strong_km + ci_medium_km  + ci_weak_km
  # + ci_foot_km
  | route_id + year,
  # | route_id,
  data = route_lts1,
  # data = route_lts2,
  cluster = ~city
)

# Trip safety LTS composite: Does infrastructure lower the average stress score? (Level-Level)
model_avg_wlts <- feols(
  route_avg_lts ~ ci_strong_km + ci_medium_km + ci_weak_km
  # + ci_foot_km 
  | route_id + year,
  # | route_id,
  data = route_lts1,
  # data = route_lts2,
  cluster = ~city 
)
etable(model_avg_wlts)

# Trip interruptions: Does infrastructure lower the average interruptions (over 100m without ci)? (Level-Level)
micro_interruptions <- feols(
  route_interruptions_count ~ ci_strong_km + ci_medium_km + ci_weak_km
  # + ci_foot_km
  | route_id + year,
  # | route_id,
  data = route_lts1,
  # data = route_lts2,
  cluster = ~city 
)
etable(micro_interruptions) # discontinuities


# distance bins as split
micro_stress_dist <- feols(
  route_avg_lts ~  ci_strong_km + ci_medium_km + ci_weak_km
  # + ci_foot_km
  | route_id + year,
  # | route_id,
  data = route_lts1,
  cluster = ~city,
  split = ~dist_cat
)
etable(micro_stress_dist)

# interruptions bins as split
micro_interruptions_dist <- feols(
  route_interruptions_count ~ ci_strong_km + ci_medium_km + ci_weak_km
  # + ci_foot_km
  | route_id + year,
  # | route_id,
  data = route_lts1,
  cluster = ~city,
  split = ~dist_cat
)
etable(micro_interruptions_dist) # discontinuities
# this is interesting for bike lanes, not so much for the other


# ==========================================
# STEP 4: PREPARE THE RESULTS FOR YOUR PAPER
# ==========================================
# Macro impacts
modelsummary(
  list("Avg Duration (Log)" = macro_duration, 
       # "Avg Circuity (Log)" = macro_circuity, 
       # "% Safe Route" = macro_safety,
       "Accessibility (Log)" = macro_access),
  coef_rename = c("log_total_ci_km" = "Total City CI (Log)",
                  "log_total_road_km" = "Total City Road Network (Log)"),
  stars = TRUE,
  title = "Macro Impact of Network Expansion on City-Wide Averages (LTS 1)",
  gof_omit = "IC|Log.Lik|F" #|RMSE
)



# Micro models
modelsummary(
  list("Log Duration" = micro_duration, 
       "Log Circuity" = micro_circuity, 
       "% LTS1 Safe" = micro_safety,
       "Stress Score" = model_avg_wlts,
       "Interruptions" = micro_interruptions),
  coef_rename = c("ci_strong_km" = "Protected cycling infra (added km)", 
                  "ci_medium_km" = "Painted lane (added km)",
                  "ci_weak_km" = "Sharrow type (added km)",
                  "ci_foot_km" = "Shared with pedestrians (added km)"),
  stars = TRUE,
  title = "Impact of 1km Infrastructure Expansion on Route Characteristics (LTS 1)",
  gof_omit = "IC|Log.Lik|F" # |RMSE ; Cleans up the bottom of the table
)
modelplot(
  list("Log Duration" = micro_duration, 
       "Log Circuity" = micro_circuity, 
       # "% LTS1 Safe" = micro_safety,
       "Stress Score" = model_avg_wlts,
       "Interruptions" = micro_interruptions),
  coef_rename = c("ci_strong_km" = "Protected cycling infra (added km)", 
                  "ci_medium_km" = "Painted lane (added km)",
                  "ci_weak_km" = "Sharrow type (added km)",
                  "ci_foot_km" = "Shared with pedestrians (added km)")
)

# for distance and safety bins
modelsummary(
  list("Stress Score" = micro_stress_dist),
  coef_rename = c("ci_strong_km" = "Protected cycling infra (added km)", 
                  "ci_medium_km" = "Painted lane (added km)",
                  "ci_weak_km" = "Sharrow type (added km)",
                  "ci_foot_km" = "Shared with pedestrians (added km)"),
  stars = TRUE,
  title = "Impact of 1km Infrastructure Expansion on Route Characteristics (LTS 1)",
  gof_omit = "IC|Log.Lik|F" # |RMSE ; Cleans up the bottom of the table
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
# ot is good for 2-5 km trips.


# The Macro Quadratic Model
# We use I(total_ci_km^2) to test if the benefit of infrastructure accelerates as the network grows.
macro_access_quad <- feols(
  log_access ~ total_ci_km + I(total_ci_km^2) + log_total_road_km
  | city + year,
  data = city_lts1
)
etable(macro_access_quad) # not conclusive



# Other exploratory models ------------------------------------------------------------------


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
etable(model_route_avg_lts)
# fixed effects
summary(fixef(model_route_safety[[1]])) #only for lts1
# plot(fixef(model_route_safety[[1]]))

# errors




coefplot(model_route_duration)
coefplot(model_route_safety)





# Plots -------------------------------------------------------------------



library(ggplot2)
library(dplyr)

# 1. Create the dataframe using your exact model results
plot_data_model <- data.frame(
  Distance = rep(c("1_Short (<2km)", "2_Medium (2-5km)", "3_Long (5-8km)", "4_VeryLong (>8km)"), each = 3),
  Infra_Type = rep(c("Protected (Strong)", "Painted (Medium)", "Sharrows (Weak)"), 4),
  Estimate = c(0.1700, 0.770, 0.772,  # Short
               0.082, 0.395, 0.402,  # Medium
               0.049, 0.229, 0.234,  # Long
               0.033, 0.146, 0.162), # Very Long
  SE = c(0.068, 0.065, 0.088,
         0.026, 0.028, 0.035,
         0.015, 0.018, 0.020,
         0.011, 0.011, 0.014)
)

# 2. Clean up factors for plotting order and calculate 95% Confidence Intervals
plot_data_model <- plot_data_model |>
  mutate(
    Distance = factor(Distance, levels = c("1_Short (<2km)", "2_Medium (2-5km)", "3_Long (5-8km)", "4_VeryLong (>8km)")),
    # Order the legend from highest stress to lowest stress
    Infra_Type = factor(Infra_Type, levels = c("Sharrows (Weak)", "Painted (Medium)", "Protected (Strong)")),
    Conf_Low = Estimate - (1.96 * SE),
    Conf_High = Estimate + (1.96 * SE)
  )

# 3. Build the presentation-ready plot
stress_plot <- ggplot(plot_data_model, aes(x = Distance, y = Estimate, group = Infra_Type, color = Infra_Type)) +
  # Add a baseline of zero
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50", size = 0.8) +
  # Draw the lines connecting the distances
  geom_line(size = 1.5) +
  # Add the specific estimate points
  geom_point(size = 4) +
  # Add error bars to prove they are statistically distinct
  geom_errorbar(aes(ymin = Conf_Low, ymax = Conf_High), width = 0.1, size = 1) +
  # Use an intuitive color scheme (Green = Protected, Orange = Paint, Red = Sharrows)
  scale_color_manual(values = c("Sharrows (Weak)" = "#d73027", 
                                "Painted (Medium)" = "#fc8d59", 
                                "Protected (Strong)" = "#1a9850")) +
  # Clean, slide-ready labels
  labs(
    title = "The 'Arterial Lure': Stress Penalties by Trip Distance",
    subtitle = "Paint and Sharrows ruin the low-stress nature of local trips. Protection neutralizes arterial stress.",
    x = "Total Trip Distance",
    y = "Stress Penalty (+ Route Avg LTS)",
    color = "Infrastructure Built"
  ) +
  # A clean theme perfect for PowerPoint
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "top",
    plot.title = element_text(face = "bold", size = 18),
    plot.subtitle = element_text(color = "gray30", size = 14, margin = margin(b = 15)),
    axis.text.x = element_text(face = "bold", size = 12),
    axis.title.y = element_text(margin = margin(r = 15)),
    axis.title.x = element_text(margin = margin(t = 15)),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank() # Removes vertical lines for a cleaner look
  )

# 4. Display the plot
print(stress_plot)


# other

# ==========================================
# PLOT 1: The Commuter Trade-off
# ==========================================
tradeoff_data <- data.frame(
  Metric = c("Effective Duration", "Physical Circuity"),
  Percentage = c(-1.3, 6.0) # Converted Log coefficients to percentages
)

plot_tradeoff <- ggplot(tradeoff_data, aes(x = Metric, y = Percentage, fill = Metric)) +
  geom_bar(stat = "identity", width = 0.5) +
  geom_hline(yintercept = 0, color = "black", size = 1) +
  coord_flip() + # Makes it horizontal
  scale_fill_manual(values = c("Effective Duration" = "#1f78b4", "Physical Circuity" = "#e31a1c")) +
  labs(
    title = "The Commuter Trade-off (Per 1km Protected Infra)",
    subtitle = "Cyclists accept a physical detour (+6%) to achieve an effectively faster trip (-1.3%).",
    y = "Percentage Change (%)",
    x = ""
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none",
        plot.title = element_text(face = "bold"),
        axis.text.y = element_text(face = "bold", size = 10))
print(plot_tradeoff)

ggsave("images/commuter_tradeoff.png", plot = plot_tradeoff, width = 8, height = 4, dpi = 300)

# ==========================================
# PLOT 2: The "Network Glue" (Interruptions)
# ==========================================
gaps_data <- data.frame(
  Infra_Type = factor(c("Protected (Strong)", "Painted (Medium)", "Sharrows (Weak)"),
                      levels = c("Sharrows (Weak)", "Painted (Medium)", "Protected (Strong)")),
  Estimate = c(-0.084, -0.055, 0.055),
  SE = c(0.030, 0.032, 0.060)
) |>
  mutate(
    Conf_Low = Estimate - (1.96 * SE),
    Conf_High = Estimate + (1.96 * SE),
    Significant = ifelse(Conf_Low > 0 | Conf_High < 0, "Yes", "No")
  )

plot_gaps <- ggplot(gaps_data, aes(x = Infra_Type, y = Estimate, fill = Significant)) +
  geom_bar(stat = "identity", width = 0.6, color = "black") +
  geom_errorbar(aes(ymin = Conf_Low, ymax = Conf_High), width = 0.2, size = 0.8) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black", size = 1) +
  coord_flip() +
  scale_fill_manual(values = c("Yes" = "#1a9850", "No" = "gray70")) +
  labs(
    title = "The 'Network Glue': Bridging Route Interruptions",
    subtitle = "Only protected infrastructure significantly reduces network fragmentation.",
    y = "Change in Route Interruptions (Count)",
    x = "Infrastructure Built"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none",
        plot.title = element_text(face = "bold"),
        axis.text.y = element_text(face = "bold", size = 10))

print(plot_gaps)
ggsave("images/network_glue_gaps.png", plot = plot_gaps, width = 9, height = 5, dpi = 300)
