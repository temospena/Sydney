
cd /media/rosa/Dados/GIS/Sydney/networks/osmpbf files
osmium extract -b -9.50,38.40,-8.70,39.10 geofabrik_portugal-160101.osm.pbf -o lisbon_metro_16.pbf
osmium extract -b -9.50,38.40,-8.70,39.10 geofabrik_portugal-210101.osm.pbf -o lisbon_metro_21.pbf
osmium extract -b -9.50,38.40,-8.70,39.10 geofabrik_portugal-260101.osm.pbf -o lisbon_metro_26.pbf

osmium extract -b 150.50,-34.15,151.35,-33.55 geofabrik_australia-160101.osm.pbf -o sydney_metro_16.pbf
osmium extract -b 150.50,-34.15,151.35,-33.55 geofabrik_australia-210101.osm.pbf -o sydney_metro_21.pbf
osmium extract -b 150.50,-34.15,151.35,-33.55 geofabrik_australia-260101.osm.pbf -o sydney_metro_26.pbf

osmium extract -b 2.21,48.81,2.47,48.91 geofabrik_ile-de-france-160101.osm.pbf -o paris_city_16.pbf
osmium extract -b 2.21,48.81,2.47,48.91 geofabrik_ile-de-france-210101.osm.pbf -o paris_city_21.pbf
osmium extract -b 2.21,48.81,2.47,48.91 geofabrik_ile-de-france-260101.osm.pbf -o paris_city_26.pbf