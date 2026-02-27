library(osmextract)
library(sf)
# Create a dummy function bypassing get_travel_network wrapper
custom_get_travel_network <- function(place, boundary = NULL, boundary_type = "clipsrc", 
    extra_tags = osmactive::et_active(), columns_to_remove = c("waterway", 
        "aerialway", "barrier", "manmade"), ...) 
{
    osm_highways = osmextract::oe_read(place, boundary = boundary, 
        boundary_type = boundary_type, extra_tags = extra_tags, 
        ...)
    dplyr::select(dplyr::filter(dplyr::filter(osm_highways, !is.na(highway)), 
        is.na(service)), -dplyr::matches(columns_to_remove))
}
res = custom_get_travel_network("data/osm_pbf/geofabrik_texas-160101.osm.pbf", 
             boundary=st_read("data/pipeline/austin/austin_10km.gpkg"))
print(head(res))
