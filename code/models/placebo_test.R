library(dplyr)
library(fixest)

# 1. Create the Placebo Dataset (Set seed so you get the exact same random shuffle every time)
set.seed(2026) 
placebo_data <- route_lts1 |>
  mutate(
    # Scramble the infrastructure variables randomly across the 5 million rows
    fake_ci_strong = sample(ci_strong_km),
    fake_ci_medium = sample(ci_medium_km),
    fake_ci_weak   = sample(ci_weak_km),
    fake_ci_foot   = sample(ci_foot_km)
  )

# 2. Run your most important model (The Stress/LTS Model) using the FAKE data
placebo_stress <- feols(
  route_avg_lts ~ fake_ci_strong + fake_ci_medium + fake_ci_weak + fake_ci_foot 
  | route_id + year,
  data = placebo_data,
  cluster = ~city
)

# 3. Compare the Real vs. the Fake
# (Assuming your original model is saved as `model_avg_wlts`)
etable(list("Real Data" = model_avg_wlts, "Placebo Data" = placebo_stress))

rm(placebo_data, placebo_stress)
