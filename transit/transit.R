# aim: lad Transport for NSW Sydney and get hourly frequency for each stop

library(tidyverse)
remotes::install_github("U-Shift/GTFShift")
library(GTFShift)
library(sf)

# Data --------------------------------------------------------------------

# GTFS
tnsw_url= "https://opendata.transport.nsw.gov.au/data/dataset/d1f68d4f-b778-44df-9823-cf2fa922e47f/resource/67974f14-01bf-47b7-bfa5-c7f2f8a950ca/download/full_greater_sydney_gtfs_static_0.zip"
download.file(tnsw_url, destfile = "transit/gtfs.zip")
gtfs = load_feed("transit/gtfs.zip")
### Este dataset é demasiado pesado para este pc.
### Considerar ir buscar o gtfs sem route shapes ao transitland (em vez do completo), uma vez que nao é necessário

# metropolitan limit
# https://citydata.ada.unsw.edu.au/geoserver/geonode/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=geonode%3ALGAs_Sydney_and_surrounds&outputFormat=application%2Fjson
city_limit = st_read("transit/Sydney_and_surrounds.json")
mapview::mapview(city_limit)



# frequency per stop and hour ---------------------------------------------

stop_freq = get_stop_frequency_hourly(gtfs)

