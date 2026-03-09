library(osmextract)
library(dplyr)
library(sf)
source("code/pipeline/config.R")
source("code/pipeline/04_ci_osmactive.R")

# 04_ci_osmactive.R already registers classify_custom_ci

pbf_path <- "data/osm_pbf/munich_city_26.pbf"
cat("Reading", pbf_path, "...\n")

# Use oe_read to read the lines layer, ensuring we extract bicycle_road
extra_tags <- c(osmactive::et_active(), "bicycle_road")

lines_sf <- oe_read(
    pbf_path,
    layer = "lines",
    extra_tags = extra_tags,
    quiet = FALSE
)

cat("Total lines read:", nrow(lines_sf), "\n")

# Similar logic as osmactive::get_travel_network
osm_network <- lines_sf |>
    filter(!is.na(highway))

cycle_net <- osmactive::get_cycling_network(osm_network)
cat("Cycling network features:", nrow(cycle_net), "\n")

# Classify
cycle_net_classified <- classify_custom_ci(cycle_net)

cat("Classification results:\n")
print(table(cycle_net_classified$infra5, useNA = "ifany"))

cat("Number of bicycle_road=yes:\n")
if ("bicycle_road" %in% names(cycle_net_classified)) {
    print(table(cycle_net_classified$bicycle_road, useNA = "ifany"))
} else {
    cat("bicycle_road column not found!\n")
}
