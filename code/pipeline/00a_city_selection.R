#!/usr/bin/env Rscript
# 00a_city_selection.R
# Script to systematically find 50 other cities from data/city_list.txt
# Criteria:
# - at least 100 km of CI by 2026
# - expanded CI network by 10% between 2016 and 2026
# - geographically distributed (not concentrated in one continent)

library(httr)
library(jsonlite)
library(dplyr)

# Install countrycode if not available
# if (!requireNamespace("countrycode", quietly = TRUE)) {
#   install.packages("countrycode", repos="http://cran.us.r-project.org")
# }
library(countrycode)

# Load global configuration to get target_cities
source("code/pipeline/config.R")

# Read cities list
city_list <- read.csv("data/city_list.txt", header = FALSE, stringsAsFactors = FALSE)
colnames(city_list) <- c("city", "lat", "lon", "population", "country", "iso2", "pbf_region")

# Filter out already targeted cities and NAs in latency
city_list <- city_list |>
  filter(!city %in% target_cities) |>
  filter(!is.na(lat) & !is.na(lon))

# Add continent
city_list$continent <- countrycode(city_list$country, origin = "country.name", destination = "continent")

# Ohsome API fetcher for CI length
get_ci_len <- function(lon, lat) {
  # approx 10km bounding box
  d_lat <- 10 / 111
  d_lon <- 10 / (111 * cos(lat * pi / 180))

  min_lon <- lon - d_lon
  min_lat <- lat - d_lat
  max_lon <- lon + d_lon
  max_lat <- lat + d_lat

  bbox_str <- paste(min_lon, min_lat, max_lon, max_lat, sep = ",")

  res <- tryCatch(
    {
      GET(
        "https://api.ohsome.org/v1/elements/length",
        query = list(
          bboxes = bbox_str,
          time = "2016-01-01,2026-01-01",
          filter = "highway=cycleway or cycleway=track or cycleway=lane or cycleway:both=track or cycleway:both=lane"
        ),
        timeout(15)
      )
    },
    error = function(e) {
      return(NULL)
    }
  )

  if (is.null(res) || status_code(res) != 200) {
    return(c(NA, NA))
  }

  parsed <- content(res, "parsed")
  if (is.null(parsed$result) || length(parsed$result) < 2) {
    return(c(NA, NA))
  }

  len_2016 <- parsed$result[[1]]$value
  len_2026 <- parsed$result[[2]]$value
  c(len_2016, len_2026)
}

# Keep track of reproducibility while shuffling
set.seed(42)
city_list <- city_list[sample(nrow(city_list)), ]

# Keep continents balanced, max 12 per continent (50 total / 5 continets ≈ 10)
max_cities <- 50
max_per_continent <- 12

selected_cities <- data.frame()
continent_counts <- table(city_list$continent)
continent_counts[] <- 0

cat("Starting city selection via Ohsome API...\n")

for (i in 1:nrow(city_list)) {
  if (nrow(selected_cities) >= max_cities) break

  row <- city_list[i, ]
  cont <- row$continent

  # If continent unknown, assign 'Unknown'
  if (is.na(cont)) {
    cont <- "Unknown"
    if (!"Unknown" %in% names(continent_counts)) continent_counts["Unknown"] <- 0
  }

  # Check if we reached cap for this continent
  if (continent_counts[cont] >= max_per_continent) {
    next
  }

  cat(paste0("Checking ", row$city, " (", cont, ")... "))

  lens <- get_ci_len(row$lon, row$lat)

  if (is.na(lens[1])) {
    cat("API failed. Skipping.\n")
    Sys.sleep(1) # wait a bit if fail to avoid rate limits
    next
  }

  l2016 <- lens[1]
  l2026 <- lens[2]

  cat(paste0(round(l2016, 0), "m -> ", round(l2026, 0), "m. "))

  # Condition: >= 100km in 2026 AND >= 10% expansion (1.1x)
  if (l2026 >= 100000 && l2026 >= (l2016 * 1.1)) {
    cat("ACCEPTED!\n")
    row$len_2016_km <- l2016 / 1000
    row$len_2026_km <- l2026 / 1000

    # Store it
    if (nrow(selected_cities) == 0) {
      selected_cities <- row
    } else {
      selected_cities <- rbind(selected_cities, row)
    }

    continent_counts[cont] <- continent_counts[cont] + 1
  } else {
    cat("Rejected.\n")
  }
}

cat("\nFinished!\n")
cat("Selected", nrow(selected_cities), "cities.\n")
print(selected_cities$city)

write.csv(selected_cities, "data/selected_50_cities.csv", row.names = FALSE)
cat("Results saved to data/selected_50_cities.csv\n")
