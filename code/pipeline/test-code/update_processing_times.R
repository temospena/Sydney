# Script to update processing_time_minutes in final_city_estimations.csv
# using the values found in the individual city results files.

cat("Updating processing_time_minutes from local city results...\n")

csv_path <- "data/pipeline/final_city_estimations.csv"
if (!file.exists(csv_path)) {
    stop("final_city_estimations.csv missing")
}

final_df <- read.csv(csv_path, stringsAsFactors = FALSE)

# Ensure the column exists and is numeric
if (!"processing_time_minutes" %in% names(final_df)) {
    final_df$processing_time_minutes <- NA_real_
}

# Counters for reporting
updated_count <- 0
missing_count <- 0
missing_files_count <- 0

# Loop through each row and check if we have a local csv for that timestamp
unique_runs <- unique(final_df[, c("city", "run_timestamp")])

for (i in seq_len(nrow(unique_runs))) {
    r_city <- as.character(unique_runs$city[i])
    r_ts <- as.character(unique_runs$run_timestamp[i])

    # Format city name for folder path
    city_lower <- tolower(trimws(r_city))
    local_file <- file.path("data/pipeline", city_lower, "results", paste0("estimations_", r_ts, ".csv"))

    if (file.exists(local_file)) {
        local_df <- read.csv(local_file, stringsAsFactors = FALSE)
        if ("processing_time_minutes" %in% names(local_df)) {
            # Take the first value (they should all be the same for the same timestamp)
            time_val <- local_df$processing_time_minutes[1]

            if (!is.na(time_val)) {
                # Update matching rows in final_df
                match_idx <- which(tolower(trimws(final_df$city)) == city_lower & final_df$run_timestamp == r_ts)
                final_df$processing_time_minutes[match_idx] <- time_val
                updated_count <- updated_count + length(match_idx)
            } else {
                missing_count <- missing_count + 1
            }
        } else {
            missing_count <- missing_count + 1
        }
    } else {
        missing_files_count <- missing_files_count + 1
    }
}

write.csv(final_df, csv_path, row.names = FALSE)
cat(sprintf("Successfully updated %d rows with processing_time_minutes.\n", updated_count))
cat(sprintf("Could not find processing times inside %d files.\n", missing_count))
cat(sprintf("Could not find %.d local estimation *.csv files.\n", missing_files_count))
