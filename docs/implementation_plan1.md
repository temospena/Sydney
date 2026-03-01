# Cycling Network Analysis Pipeline

The goal is to estimate how changes in cycling infrastructure benefit cycling performance, safety, and accessibility across cities. We will first apply this pipeline to Lisbon, Sydney, Paris, and Barcelona to account for local memory and storage constraints, leaving it ready to scale to 100 cities globally.

## Proposed Changes

We will build the new pipeline in a separate folder (`code/test-pipeline/`) so we do not delete or overwrite the user's initial test scripts (`od_data.R`, `city_buffers.R`, etc.).

### Phase 1: Data Preparation
- **City Boundaries**: Create `code/test-pipeline/00_city_buffers.R` to automatically generate 10km buffers for Lisbon, Sydney, Paris, and Barcelona from `city_list.txt` and save them. 
- **Origins/Destinations**: Create `code/test-pipeline/01_od_data.R` to take the generated 10km buffers, extract buildings data, generate 20k O/D pairs weighted by volume, and save them. 
- **OSM Data Extraction**: Create `code/test-pipeline/02_historical_osm.R` to automate osmium cropping using the 10km buffer bounding boxes. *Fallback*: If raw historical data is unavailable locally, `osmextract::oe_download` will fetch the area as a temporary object and safely unlink it upon completing the `osmium` crop to respect storage.

*Cleanup Strategy*: Delete intermediate files (like large GeoJSON building files or raw country PBFs downloaded temporarily via `osmextract`) if they exceed ~5MB once the required small outputs (like OD CSVs or cropped city PBFs) are generated.

### Phase 2: Routing Phase (r5r)
- **Network Setup & Routing Engine**: Create `code/test-pipeline/03_r5r_routing.R` to process routing for each city and year (2016, 2021, 2026), looping sequentially. 
- *Cleanup Strategy*: Use `gc()` and delete raw itineraries from disk/RAM iteratively. Leave only `.dat` networking files, summary CSVs, and plots.

### Phase 3: Analysis & Visualization
- **Circuity & Accessibility**: Create `code/test-pipeline/04_analysis.R` to calculate distances, circuity, and `overline2` estimates.
- Keep all plots and images and save them to the results directory. Clean up large spatial dataframes after plotting.

## Verification Plan

### Automated Tests
- Iterate through the full pipeline for one lightweight city to confirm outputs and memory constraints. 
### Manual Verification
- Render plots and inspect final CSV structure.
