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
  # filter(!city %in% target_cities) |>
  filter(!is.na(lat) & !is.na(lon))

# Add continent
city_list$continent <- countrycode(city_list$country, origin = "country.name", destination = "continent")

# Ohsome API fetcher for CI length at a specific date
get_ci_len <- function(lon, lat, time_str) {
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
          time = time_str,
          filter = "highway=cycleway or cycleway=track or cycleway=lane or cycleway:both=track or cycleway:both=lane"
        ),
        timeout(45) # increased timeout
      )
    },
    error = function(e) {
      return(NULL)
    }
  )

  if (is.null(res) || status_code(res) != 200) {
    return(NA)
  }

  parsed <- content(res, "parsed")
  if (is.null(parsed$result) || length(parsed$result) < 1) {
    return(NA)
  }

  return(parsed$result[[1]]$value)
}

# Keep track of reproducibility while shuffling
set.seed(42)
city_list <- city_list[sample(nrow(city_list)), ]

# Keep continents balanced, max 12 per continent (50 total / 5 continets ≈ 10)
# max_cities <- 50
# max_per_continent <- 12

selected_cities <- data.frame()
continent_counts <- table(city_list$continent)
continent_counts[] <- 0

cat("Starting city selection via Ohsome API...\n")

progress_file <- "data/city_selection_progress.csv"
if (file.exists(progress_file)) {
  progress <- read.csv(progress_file, stringsAsFactors = FALSE)
  # Remove successfully evaluated (ACCEPTED or REJECTED) cities from the to-do list
  # FAILED ones remain so we can retry them
  done_cities <- progress$city[progress$status != "FAILED"]
  city_list <- city_list |> filter(!city %in% done_cities)

  # Load the accepted cities into selected_cities and reconstruct continent counts
  accepted <- progress[progress$status == "ACCEPTED", ]
  if (nrow(accepted) > 0) {
    # remove the 'status' column so it matches the expected columns
    selected_cities <- accepted |> select(-status)
    for (c in selected_cities$continent) {
      if (!is.na(c) && c %in% names(continent_counts)) {
        continent_counts[c] <- continent_counts[c] + 1
      }
    }
  }
  cat("Resuming from previous progress! Loaded", nrow(selected_cities), "already accepted cities.\n")
} else {
  progress <- data.frame()
}

for (i in 1:nrow(city_list)) {
  # if (nrow(selected_cities) >= max_cities) break

  row <- city_list[i, ]
  cont <- row$continent

  # If continent unknown, assign 'Unknown'
  if (is.na(cont)) {
    cont <- "Unknown"
    if (!"Unknown" %in% names(continent_counts)) continent_counts["Unknown"] <- 0
  }

  # Check if we reached cap for this continent
  # if (continent_counts[cont] >= max_per_continent) {
  #   next
  # }

  cat(paste0("Checking ", row$city, " (", cont, ")... 2026: "))

  l2026 <- get_ci_len(row$lon, row$lat, "2026-01-01")

  if (is.na(l2026)) {
    cat("API failed. Skipping for now.\n")
    row$status <- "FAILED"
    row$len_2016_km <- NA
    row$len_2026_km <- NA

    # Remove previous failed records for this city if any, to avoid duplicates
    progress <- progress[progress$city != row$city, ]
    progress <- rbind(progress, row)
    write.csv(progress, progress_file, row.names = FALSE)

    Sys.sleep(5) # wait longer to avoid rate limits
    next
  }

  cat(paste0(round(l2026, 0), "m. "))

  # Remove previous failed records for this city if any
  progress <- progress[progress$city != row$city, ]

  # Condition: >= 100km in 2026
  if (l2026 < 100000) {
    cat("Rejected (< 100km CI).\n")
    row$status <- "REJECTED"
    row$len_2016_km <- NA
    row$len_2026_km <- l2026 / 1000
    progress <- rbind(progress, row)
  } else {
    # If 2026 is good, check 2016
    cat(">=100km! Checking 2016... ")
    Sys.sleep(2.5) # limit api calls

    l2016 <- get_ci_len(row$lon, row$lat, "2016-01-01")
    if (is.na(l2016)) {
      cat("API failed on 2016. Skipping for now.\n")
      row$status <- "FAILED"
      row$len_2016_km <- NA
      row$len_2026_km <- l2026 / 1000
      progress <- rbind(progress, row)
      write.csv(progress, progress_file, row.names = FALSE)
      Sys.sleep(5)
      next
    }

    cat(paste0(round(l2016, 0), "m. "))
    row$len_2016_km <- l2016 / 1000
    row$len_2026_km <- l2026 / 1000

    if (l2026 >= (l2016 * 1.1)) {
      cat("ACCEPTED!\n")
      row$status <- "ACCEPTED"
      progress <- rbind(progress, row)

      # Store it (without status column for final output)
      clean_row <- row |> select(-status)
      if (nrow(selected_cities) == 0) {
        selected_cities <- clean_row
      } else {
        selected_cities <- rbind(selected_cities, clean_row)
      }

      continent_counts[cont] <- continent_counts[cont] + 1
    } else {
      cat("Rejected (< 10% expansion).\n")
      row$status <- "REJECTED"
      progress <- rbind(progress, row)
    }
  }

  write.csv(progress, progress_file, row.names = FALSE)

  Sys.sleep(3) # Safe delay between requests
}

cat("\nFinished!\n")
cat("Selected", nrow(selected_cities), "cities.\n")
print(selected_cities$city)

write.csv(selected_cities, "data/selected_50_cities.csv", row.names = FALSE)
cat("Results saved to data/selected_50_cities.csv\n")
