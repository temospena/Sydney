# 06_tidy_up.R
# Tidy up large intermediate routing .rds results

# Load global configuration
source("code/test-pipeline/config.R")

cat("Starting Tidy Up Phase...\n")

for (city in target_cities) {
  city_lower <- tolower(city)
  city_dir <- file.path(data_dir, city_lower)
  
  cat("Tidying up", city, "...\n")
  for (yr in years) {
    for (lts_level in 1:4) {
      res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
      if (file.exists(res_file)) {
        file.remove(res_file)
        cat("  Removed:", basename(res_file), "\n")
      }
    }
  }
}

cat("Tidy up complete.\n")
