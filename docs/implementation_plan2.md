# Implementing Plan 2 recommendations

This plan addresses all the points mentioned in [docs/plan2.txt](file:///home/rosa/GIS/Sydney/docs/plan2.txt) based on our agreed strategy.

## Proposed Changes

---

### Architecture & Versioning

Instead of blindly overriding old files, we will create a clear separation.
- Tag current main as a release (`v1.0-lts`).
- Checkout a new branch `routing-v2`.
- We will create `code/pipeline_v2/` to host the new routing and OD scripts, while leaving `code/pipeline/` intact.

### OD Generation

We will integrate the drafts from `data_od_ddecay.R` and `od_grid.R`.

#### [NEW] [02_od_data_v2.R](file:///home/rosa/GIS/Sydney/code/pipeline_v2/02_od_data_v2.R)
- Group building destinations into an H3 grid (resolution 9 = ~400m diameter).
- Generate random target distances following a lognormal distribution (µ=0.33, σ=0.66).
- Select unweighted origins from a "donut" H3 ring matching that target distance.
- Calculate circuity based on H3 cell centroids instead of building points.

### BRouter Routing

#### [NEW] [docker-compose.yml](file:///home/rosa/GIS/Sydney/docker-compose.yml)
A compose file to spin up BRouter instances on different ports (e.g., 17771, 17772, 17773) mapping to `data/brouter/segments_2016`, `_2021`, `_2026`. Designed to be easily extensible for future years like 2018 and 2023.

#### [NEW] [cycling_ci.brf](file:///home/rosa/GIS/Sydney/code/pipeline_v2/cycling_ci.brf)
A custom BRouter profile. This profile will parse highway and cycleway tags and map them directly using the costs in `code/old/od2net-osm-costs`, and scaling our 4 categories:
1. `strong_ci` (Lowest cost / most attractive)
2. `moderate_ci`
3. `weak_ci`
4. `shared_foot`
Elevation features will be ignored by setting the relevant cost factors to 0.

#### [NEW] [build_brouter_segments.sh](file:///home/rosa/GIS/Sydney/code/pipeline_v2/build_brouter_segments.sh)
A shell script using `osmium` to:
1. Concatenate all 50 city `.osm.pbf` files per year into a master PBF for the year.
2. Run the BRouter Segment Creator on the master files to output `.rd5` tiles.

#### [NEW] [03_routing_brouter.R](file:///home/rosa/GIS/Sydney/code/pipeline_v2/03_routing_brouter.R)
An R script that:
1. Reads the H3 OD grid.
2. Uses `mclapply` (or `furrr`) to parallel-query the local BRouter API instances.
3. Parses the returned GeoJSON/JSON to extract shapes and OSM IDs.

### Pipeline Integration

#### [NEW] [05_estimations_v2.R](file:///home/rosa/GIS/Sydney/code/pipeline_v2/05_estimations_v2.R)
- Appends results to a new file `final_city_estimations_v2.csv`.
- Expected variables to include: `run_timestamp`, `avg_distance_m`, `avg_circuity`, `avg_dist_change_pct`, `pct_ci_route`, `pct_ci_route_type_strong_ci`, `pct_ci_route_type_moderate_ci`, `pct_ci_route_type_weak_ci`, `pct_ci_route_type_shared_foot`, `avg_duration_min`, `access_15min_vol`, `found_routes`, `processing_time_minutes`. (Removing LTS-specific ones since LTS is no longer used).
- Removes plot generation.

## Verification Plan

### Automated Tests
- Run `02_od_data_v2.R` locally for Chicago and verify the OD trip length distribution roughly matches the target lognormal distribution.

### Manual Verification
- Run `build_brouter_segments.sh` locally for Chicago and Lisbon.
- Spin up the BRouter docker containers locally.
- Run `03_routing_brouter.R` for Chicago and visualize a subset of the generated routes in QGIS or Mapview to visually confirm they favor `strong_ci` links.
