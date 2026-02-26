prefixes <- c(
 "europe/france", "europe/france/rhone-alpes",
 "asia/china", 
 "europe/spain", "europe/spain/comunidad-de-madrid",
 "europe/france/languedoc-roussillon",
 "europe/united-kingdom/england/west-yorkshire", "europe/great-britain/england/west-yorkshire", "europe/great-britain/england"
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
