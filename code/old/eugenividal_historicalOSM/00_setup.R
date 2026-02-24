## R/00_setup.R
## Global setup for a single city (edit to switch cities)

# Packages ---------------------------------------------------------------
# remotes::install_github("nptscot/osmactive")

suppressPackageStartupMessages({
  library(sf)
  library(osmdata)
  library(tidyverse)
  library(osmextract)
  library(osmactive)
  library(leaflet)
  library(htmltools)
})

# Options ----------------------------------------------------------------

options(sf_use_s2 = FALSE) # planar operations

# ----------------------------------------------------------------------
# CITY SETTINGS: edit this block to run the workflow for a different city
# ----------------------------------------------------------------------

# one each time, and then run the 02, 03, and 04

city_name           <- "Lisboa"
city_tag            <- "lisbon"
city_boundary_place <- "Lisboa, Portugal"
infra_region <- "Portugal"
crs_work <- 3763

city_name           <- "Sydney"
city_tag            <- "sydney"
city_boundary_place <- "Sydney, Australia"
infra_region <- "Australia" #"New South Wales"
crs_work <- 7856

# 
# 
# city_name           <- "Barcelona"
# city_tag            <- "barcelona"
# city_boundary_place <- "Barcelona, Spain"
# infra_region <- "Spain"
# crs_work <- 25831

city_name           <- "Paris"
city_tag            <- "paris"
city_boundary_place <- "Paris, France"
infra_region <- "Île-de-France"
crs_work <- 2154

# city_name           <- "Montréal"
# city_tag            <- "montreal"
# city_boundary_place <- "Montréal, Canada"
# infra_region <- "Québec"
# crs_work <- 26918

# -----------------------------
# Settings (edit)
# -----------------------------

FORCE_BUILD <- FALSE              # TRUE = re-download/rebuild even if files exist
VERSIONS <- c("160101","210101", "260101") # snapshots to ensure exist (edit as needed)
