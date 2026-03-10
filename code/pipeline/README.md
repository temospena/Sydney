# Code Pipeline - CI Analysis Scripts

This directory contains the R scripts used to run the Cycling Infrastructure (CI) analysis pipeline.

## Pipeline Workflow

The pipeline is designed to be run end-to-end for a list of cities defined in `config.R`. The process follows these stages:
1. **Extraction:** Clipping OSM data and extracting CI networks.
2. **Routing:** Calculating O/D matrices using `r5r`.
3. **Analysis:** Estimating travel distances, circuity, and accessibility.
4. **Visualization:** Generating maps and statistical plots.

## Configuration (`config.R`)

Before running the pipeline, review and modify the user settings in `config.R`:
- `target_cities`: Vector of city names to process (e.g., `c("Sydney", "Lisbon")`).
- `years`: Target years (e.g., `c("16", "21", "26")`).
- `lts_levels`: LTS thresholds to route (e.g., `1:4`).
- `n_od_pairs`: Number of random O/D pairs to sample (standard is `20000`).
- `FORCE_RERUN`: If `TRUE`, it will re-process everything even if files exist.
- `REROUTE_ONLY`: If `TRUE`, it only re-runs the routing step.
- `h3_res`: H3 resolution used for spatial aggregation and OD sampling (default is `9`).
- `mu_log` & `sd_log`: Parameters for the log-normal trip distance decay (v4 sampling approach).
- `ci_colors`: Shared color palette and names for the 4 custom CI categories (Separated, Painted, Mixed, Pedestrian).

> [!IMPORTANT]
> **Adding a New City:**
> To add a new city, you must update two files:
> 1. **`data/geofabrik_regions.csv`**: Add the relative Geofabrik path for each target year. **Critical:** Use the smallest available geographical unit for that year (e.g., use `cataluna` for 2024, but fallback to `spain` for 2016).
> 2. **`data/city_list.txt`**: Add the city name, coordinates, and population if it is not already present.
>
> If these are missing, the pipeline will fail to download data or estimate final population-weighted metrics.


## How to Run

### Execute Full Pipeline
To run the entire process (Extraction → Routing → Analysis → Plots) for all enabled cities:
```bash
Rscript code/pipeline/00_run_all_v4od.R
```

> [!TIP]
> **Preferable Version:** `00_run_all_v4od.R` is generally preferred as it implements the "v4" OD sampling logic (using lognormal distance decay).


### Refresh Plots Only
If metrics have already been calculated and you only want to update visualizations:
```bash
Rscript code/pipeline/00_run_plots_only.R
```

### Server-Side Cleanup
Intermediate routing files (`.rds`) can be very large (~1GB per city). To wipe these caches after a successful run:
```bash
Rscript code/pipeline/11_tidy_up.R
```

## Script Inventory
- `01_city_buffers.R`: Creates study area boundaries.
- `02_od_data.R`: Samples O/D pairs weighted by building volume.
- `03_historical_routing_osm.R`: Prepares OSM `.pbf` files for [`r5r`](https://ipeagit.github.io/r5r/).
- `04_ci_osmactive.R`: Classifies cycling infrastructure into 4 custom categories using the [`osmactive`](https://github.com/nptscot/osmactive) package logic.
- `05_r5r_routing.R`: Core routing engine usage for O/D matrix calculation.
- `06_accessibility.R`: Estimates building-weighted accessibility volumes (15-min).
- `07_analysis.R`: Main analysis script for distance, circuity, and CI usage metrics.
- `07b_analysis_plots.R`: Contrast/comparison plots and histograms for routing results.
- `08_final_metrics.R`: Consolidates all results into the global CSV.
- `09_plot_metrics.R`: Generates infrastructure breakdown and usage charts.
- `10_ci_maps.R`: Generates high-resolution facet maps showing the spatial evolution of CI.

