
library(tidyverse)
library(sf)
library(mapview)

# sydney ------------------------------------------------------------------

sydney_ci_omsactive_20260101 = st_read("data/sydney/sydney_ci_osmactive_260101.gpkg", quiet = TRUE)
sydney_ci_omsactive_20210101 = st_read("data/sydney/sydney_ci_osmactive_210101.gpkg", quiet = TRUE)
sydney_ci_omsactive_20160101 = st_read("data/sydney/sydney_ci_osmactive_160101.gpkg", quiet = TRUE)

sydney_ci_omsactive_20260101 == sydney_ci_omsactive_20160101

mapview(sydney_ci_omsactive_20260101) + mapview(sydney_ci_omsactive_20160101, col.regions = "red")

# they are not different!



# lisbon ------------------------------------------------------------------

lisbon_ci_omsactive_20260101 = st_read("data/lisbon/lisbon_ci_osmactive_260101.gpkg", quiet = TRUE)
lisbon_ci_omsactive_20210101 = st_read("data/lisbon/lisbon_ci_osmactive_210101.gpkg", quiet = TRUE)
lisbon_ci_osmactive_20160101 = st_read("data/lisbon/lisbon_ci_osmactive_160101.gpkg", quiet = TRUE)
