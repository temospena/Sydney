# aim: select randomly 100 cities from the data/city_list.txt 
# create buffer of 5km radious (crs 3857) from the lat/lon

library(dplyr)
library(sf)
sf_use_s2(TRUE)
library(mapview)

city_list = read.csv("~/GIS/Sydney/data/city_list.txt", header=FALSE)
city_list = city_list |> 
  rename(city = V1,
         lat = V2,
         lon = V3,
         population =V4,
         country = V5,
         country_code = V6) |> 
  st_as_sf(crs=4326, coords = c("lon", "lat"))

mapview(city_list)           
summary(city_list$population)

city_list_sample = city_list |> 
  filter(population > 1000000) # more that 1M
  # sample(100)

city_list_sample_area = city_list_sample |>
  st_transform(3857) |>
  st_buffer(dist = 10000) |> # 10 km
  st_transform(4326)

mapview(city_list_sample_area, zcol = "population")


