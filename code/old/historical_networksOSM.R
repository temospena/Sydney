
library(tidyverse)
library(sf)
library(mapview)

# sydney ------------------------------------------------------------------

sydney_ci_omsactive_20260101 = st_read("data/sydney/sydney_ci_osmactive_260101.gpkg", quiet = TRUE)
sydney_ci_omsactive_20210101 = st_read("data/sydney/sydney_ci_osmactive_210101.gpkg", quiet = TRUE)
sydney_ci_omsactive_20160101 = st_read("data/sydney/sydney_ci_osmactive_160101.gpkg", quiet = TRUE)


# lisbon ------------------------------------------------------------------

lisbon_ci_omsactive_20260101 = st_read("data/lisbon/lisbon_ci_osmactive_260101.gpkg", quiet = TRUE)
lisbon_ci_omsactive_20210101 = st_read("data/lisbon/lisbon_ci_osmactive_210101.gpkg", quiet = TRUE)
lisbon_ci_osmactive_20160101 = st_read("data/lisbon/lisbon_ci_osmactive_160101.gpkg", quiet = TRUE)


# paris ------------------------------------------------------------------

paris_ci_omsactive_20260101 = st_read("data/paris/paris_ci_osmactive_260101.gpkg", quiet = TRUE)
paris_ci_omsactive_20210101 = st_read("data/paris/paris_ci_osmactive_210101.gpkg", quiet = TRUE)
paris_ci_osmactive_20160101 = st_read("data/paris/paris_ci_osmactive_160101.gpkg", quiet = TRUE)