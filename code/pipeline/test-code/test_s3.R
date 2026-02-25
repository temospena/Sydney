library(sf)
source("code/pipeline/config.R")
city_list_path <- "../../data/city_list.txt"
city_list <- read.csv(city_list_path, header = FALSE) |> 
  rename(city = V1, lat = V2, lon = V3)

get_tile <- function(city_name) {
   row <- city_list[city_list$city == city_name, ]
   if(nrow(row) == 0) return(NA)
   
   lon <- row$lon
   lat <- row$lat
   
   # calculate 5 deg tile
   lon_floor <- floor(lon / 5) * 5
   lon_ceil <- lon_floor + 5
   lat_floor <- floor(lat / 5) * 5
   lat_ceil <- lat_floor + 5
   
   lon_p1 <- ifelse(lon_floor < 0, paste0("w", sprintf("%03d", abs(lon_floor))), paste0("e", sprintf("%03d", lon_floor)))
   lat_p1 <- ifelse(lat_ceil < 0, paste0("s", sprintf("%02d", abs(lat_ceil))), paste0("n", sprintf("%02d", lat_ceil)))
   lon_p2 <- ifelse(lon_ceil < 0, paste0("w", sprintf("%03d", abs(lon_ceil))), paste0("e", sprintf("%03d", lon_ceil)))
   lat_p2 <- ifelse(lat_floor < 0, paste0("s", sprintf("%02d", abs(lat_floor))), paste0("n", sprintf("%02d", lat_floor)))
   
   return(paste(lon_p1, lat_p1, lon_p2, lat_p2, sep="_"))
}

print("Munich:"); print(get_tile("Munich"))
print("London:"); print(get_tile("London"))
print("New York:"); print(get_tile("New York"))
print("Sao Paulo:"); print(get_tile("Sao Paulo"))

