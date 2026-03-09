# Data Pipeline - Cities Data

This directory contains the processed data for each city included in the Cycling Infrastructure (CI) analysis.

## Directory Structure

Each city has its own folder (e.g., `sydney/`, `lisbon/`, `paris/`, `barcelona/`). Inside each city folder, the structure is organized as follows:

### Input and Intermediate Spatial Data
- `origins.gpkg`: Sampled origin points (buildings) with coordinates.
- `destinations.gpkg`: Sampled destination points (buildings) with coordinates.
- `CITY_10km.gpkg`: 10km buffer boundary for the city's study area.
- `CITY_ci_osmactive_YY0101.gpkg`: Vector network of cycling infrastructure extracted for year `YY`.
- `land_use.gpkg`: Building footprints and other relevant land use layers.

### Routing Infrastructure
- `r5r_YY/`: Directory containing the `r5r` routing graph (`network.dat`) for year `YY`.
- `trips_CITY_YY_ltsX.rds`: Compressed R data files containing routing results for a specific year and LTS level. 
  > [!NOTE]
  > These files are often pruned by `11_tidy_up.R` after metric estimation to save disk space.
- `routing_summary.csv`: Summary of successfully routed O/D pairs per year and LTS level.

### Results and Visualizations (`results/`)
This folder contains all outputs from the analysis and plotting scripts:
- **Maps:**
  - `overline_map_ltsX.png`: Visualizes trip density on segments for a specific LTS level.
  - `ci_evolution_facet_map.png`: A multi-year dashboard showing the expansion of CI.
  - `od_hex_map.png`: Density of Origin/Destination pairs in a hexagonal grid.
- **Charts:**
  - `plot_route_lts_usage.png`: Breakdown of LTS levels actually used in recommended routes.
  - `plot_ci_types_absolute.png`: Growth of different CI types in kilometers over time.
  - `distance_change_histogram_ltsX.png`: Distribution of travel distance changes.
- **Tables:**
  - `estimations_YYYYMMDD_HHMMSS.csv`: Timestamped snapshots of city-specific metrics.

## Global Aggregated Data
- `final_city_estimations.csv`: The master table located in `data/pipeline/` that aggregates metrics from all cities, years, and LTS levels into a single comparative dataset.
