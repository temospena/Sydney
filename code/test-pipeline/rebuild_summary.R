# rebuild_summary.R
# Rebuild routing_summary.csv from existing .rds files

library(tidyverse)

data_dir <- path.expand("~/GIS/Sydney/data/test-pipeline")
city <- "Sydney"
city_lower <- tolower(city)
city_dir <- file.path(data_dir, city_lower)
years <- c(16, 21, 26)

results_summary <- list()

for (yr in years) {
  for (lts_level in 1:4) {
    res_file <- file.path(city_dir, paste0("trips_", city_lower, "_", yr, "_lts", lts_level, ".rds"))
    if (file.exists(res_file)) {
      trips <- readRDS(res_file)
      found_routes <- nrow(trips)
      avg_dist_km <- round(mean(trips$total_distance, na.rm = TRUE) / 1000, 2)
      
      results_summary[[paste0(yr, lts_level)]] <- data.frame(
        city = city_lower,
        year = yr,
        lts = lts_level,
        found_routes = found_routes,
        avg_dist_km = avg_dist_km
      )
      rm(trips); gc()
    }
  }
}

final_summary <- bind_rows(results_summary)
write.csv(final_summary, file.path(city_dir, "routing_summary.csv"), row.names = FALSE)
cat("routing_summary.csv rebuilt successfully.\n")
