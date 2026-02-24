# r5r setup for all networks and years

# Load packages
library(tidyverse)
library(sf)
options(java.parameters = '-Xmx96G') # allocate memory for 8GB 
library(r5r)
path_r5r <- "networks/r5r/"

# Deliberately not using elevation (focous only in geometric problems) and GTFS (not needed)

# For Lisbon
r5_lisbon16 <- setup_r5(data_path = paste0(path_r5r, "lisbon_16"),verbose = TRUE)
r5_lisbon21 <- setup_r5(data_path = paste0(path_r5r, "lisbon_21"),verbose = TRUE)
r5_lisbon26 <- setup_r5(data_path = paste0(path_r5r, "lisbon_26"),verbose = TRUE)

# For Sydney
r5_sydney16 <- setup_r5(data_path = paste0(path_r5r, "sydney_16"),verbose = TRUE)
r5_sydney21 <- setup_r5(data_path = paste0(path_r5r, "sydney_21"),verbose = TRUE)
r5_sydney26 <- setup_r5(data_path = paste0(path_r5r, "sydney_26"),verbose = TRUE)

# For Paris
r5_paris16 <- setup_r5(data_path = paste0(path_r5r, "paris_16"),verbose = TRUE)
r5_paris21 <- setup_r5(data_path = paste0(path_r5r, "paris_21"),verbose = TRUE)
r5_paris26 <- setup_r5(data_path = paste0(path_r5r, "paris_26"),verbose = TRUE)



# extract LTS for each one ------------------------------------------------

# The lts column will be present in the resulting object

r5_lisbon16 |> street_network_to_sf() |> purrr::pluck("edges") |> st_write("networks/lts/lisbon16_lts.gpkg")
r5_lisbon21 |> street_network_to_sf() |> purrr::pluck("edges") |> st_write("networks/lts/lisbon21_lts.gpkg")
r5_lisbon26 |> street_network_to_sf() |> purrr::pluck("edges") |> st_write("networks/lts/lisbon26_lts.gpkg")

r5_sydney16 |> street_network_to_sf() |> purrr::pluck("edges") |> st_write("networks/lts/sydney16_lts.gpkg")
r5_sydney21 |> street_network_to_sf() |> purrr::pluck("edges") |> st_write("networks/lts/sydney21_lts.gpkg")
r5_sydney26 |> street_network_to_sf() |> purrr::pluck("edges") |> st_write("networks/lts/sydney26_lts.gpkg")

r5_paris16 |> street_network_to_sf() |> purrr::pluck("edges") |> st_write("networks/lts/paris16_lts.gpkg")
r5_paris21 |> street_network_to_sf() |> purrr::pluck("edges") |> st_write("networks/lts/paris21_lts.gpkg")
r5_paris26 |> street_network_to_sf() |> purrr::pluck("edges") |> st_write("networks/lts/paris26_lts.gpkg")



# stop --------------------------------------------------------------------

stop_r5() # by default, all will be stopped
rJava::.jgc(R.gc = TRUE)