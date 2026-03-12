# Sydney - Cycling Infrastructure (CI) Evaluation Pipeline

This repository contains an automated, scalable pipeline designed to analyze the evolution of cycling infrastructure and its impact on safety, trip performance, interruptions, and accessibility across global cities. The project evaluates how changes in the cycling network (Stress levels, infrastructure types) translate into travel time and distance efficiencies for commuters.

## Repository Overview

- [**code/pipeline/**](code/pipeline/): Core R scripts for data extraction, historical routing (`r5r`), accessibility analysis, and visualization.
- [**data/pipeline/**](data/pipeline/): Processed spatial datasets, city-specific results, and the master aggregated metrics table.
- [**docs/**](docs/): Technical documentation, including all the AI prompts used to scale up the pipeline, pipeline flowcharts (`.drawio`) and project development plans.
- [**images/**](images/): High-level visualizations, research snapshots, and consolidated plots for all studied cities.
- [**paper/**](paper/): Manuscript and research note source files (`.qmd`, `.bib`).
- [**slides/**](slides/): Presentation slides (`.qmd`, `.html`).

## Key Features

- **Multi-Year Analysis:** Tracks infrastructure growth across 2016, 2019, 2021, 2024, and 2026.
- **Stress-Based Routing:** Uses R5 Level of Traffic Stress (LTS 1-4) thresholds.
- **Accessibility Metrics:** Computes 15-minute building-weighted accessibility volumes.
- **Modelling:** Prepares panel data for modelling, at city and route levels.
- **Automated Visualization:** Generates infrastructure evolution charts, facet maps, and overline density plots.

## Getting Started

### Prerequisites
- **R** (with packages: `sf`, `r5r`, `ggplot2`, `dplyr`, `tmap`, `stplanr`, `fixest`, `h3jsr`, `osmactive`, `duckdb`)
- **Java** (required for `r5r` engine)
- **Osmium Tool** (for PBF clipping)

### Basic Usage
1.  Define your target cities and parameters in `code/pipeline/config.R`.
2.  Run the full pipeline:
    ```bash
    Rscript code/pipeline/00_run_all_v4od.R
    ```
3.  View the aggregated results in `data/pipeline/final_city_estimations.csv`.

For detailed documentation on data structure and script functions, please refer to the README files in the [**code/**](code/pipeline/README.md) and [**data/**](data/pipeline/README.md) directories.

---

## Collaborating Institutions

<table width="100%">
  <tr>
    <td align="center" width="50%">
      <img src="slides/images/ushift-logo.jpeg" alt="U-Shift Logo" width="250" />
      <br />
      <b>CERIS - Instituto Superior Técnico</b>
      <br />
      University of Lisbon
      <br />
      Rosa Félix
    </td>
    <td align="center" width="50%">
      <img src="slides/images/transportlab.png" alt="TransportLab Logo" width="250" />
      <br />
      <b>TransportLab</b>
      <br />
      University of Sydney
      <br />
      David Levinson
    </td>
  </tr>
</table>

---

## Acknowledgments

This research was funded by **FCT - Fundação para a Ciência e Tecnologia** under the FCT-Mobility program (FCT/Mobility/1302410540/2024-25).

<p align="center">
  <img src="slides/images/logo_fct_black.svg" height="50" alt="FCT Logo" />
  &nbsp;&nbsp;&nbsp;
  <img src="slides/images/RepublicaPortuguesa.svg" height="50" alt="República Portuguesa" />
  &nbsp;&nbsp;&nbsp;
  <img src="slides/images/prr.svg" height="50" alt="PRR" />
  &nbsp;&nbsp;&nbsp;
  <img src="slides/images/eu_NextGeneration.svg" height="50" alt="EU NextGeneration" />
</p>
