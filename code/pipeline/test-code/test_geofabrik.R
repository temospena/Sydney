prefixes <- c(
 "europe/france/auvergne-rhone-alpes", "asia/south-korea", "africa/egypt", 
 "asia/china/shanghai", "europe/italy/nord-est", "africa/south-africa-and-lesotho", 
 "europe/spain/madrid", "australia-oceania/australia", "europe/austria", 
 "europe/norway", "europe/ireland-and-northern-ireland", "asia/taiwan", 
 "europe/italy/nord-ovest", "europe/france/occitanie", "europe/sweden", 
 "south-america/argentina", "europe/slovenia", "europe/great-britain/england/west-yorkshire", 
 "europe/switzerland", "europe/poland", "north-america/us/illinois", 
 "north-america/us/texas", "europe/france/alsace", "asia/japan/kansai"
)

for (p in prefixes) {
  url <- paste0("http://download.geofabrik.de/", p, "-210101.osm.pbf")
  req <- try(httr::HEAD(url), silent=TRUE)
  if (inherits(req, "try-error") || req$status_code != 200) {
    if (!inherits(req, "try-error") && req$status_code == 404) {
      cat(paste(p, "404 Not Found\n"))
    } else {
      cat(paste(p, "Error/Other status\n"))
    }
  } else {
    cat(paste(p, "OK\n"))
  }
}
