library(osmextract)
library(osmactive)
library(sf)
# download a small pbf to test
pbf_url <- "https://download.geofabrik.de/europe/andorra-latest.osm.pbf"
dest <- "andorra.osm.pbf"
download.file(pbf_url, dest, quiet=TRUE)

get_travel_network(place = dest, quiet = FALSE)
