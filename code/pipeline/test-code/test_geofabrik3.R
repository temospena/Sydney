prefixes <- c("europe/france/rhone-alpes", "europe/france/languedoc-roussillon", "europe/united-kingdom/england/west-yorkshire")
for (y in c("16", "21", "26")) {
    for (p in prefixes) {
        url <- paste0("http://download.geofabrik.de/", p, "-", y, "0101.osm.pbf")
        req <- try(httr::HEAD(url), silent = TRUE)
        if (!inherits(req, "try-error") && req$status_code == 200) {
            cat(paste(p, y, "OK\n"))
        } else {
            cat(paste(p, y, "FAIL\n"))
        }
    }
}
