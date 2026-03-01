#!/bin/bash
echo "=== Running 02_od_data_v2.R ==="
Rscript -e 'city_to_run="Lisbon"; source("code/pipeline_v2/02_od_data_v2.R")'

echo "=== Running 03_routing_brouter.R and timing it ==="
time Rscript -e 'city_to_run="Lisbon"; source("code/pipeline_v2/03_routing_brouter.R")'

echo "=== Running 05_estimations_v2.R ==="
Rscript -e 'city_to_run="Lisbon"; source("code/pipeline_v2/05_estimations_v2.R")'
