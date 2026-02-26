prefixes <- c("europe/spain/madrid", "europe/spain/centro", "asia/china")
for (y in c("16", "21", "26")) {
    for (p in prefixes) {
        url <- paste0("http://download.geofabrik.de/", p, "-", y, "0101.osm.pbf")
        req <- try(httr::HEAD(url), silent = TRUE)
        if (!inherits(req, "try-error") && req$status_code == 200) {
            cat(paste(p, y, "OK\n"))
        }
    }
}
