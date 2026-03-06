#!/bin/bash

# organize_images.sh
# Script to collect plot results from data/pipeline folders and organize them into images/ for easier viewing.
# These folders are added to .gitignore to prevent repo bloat.

PROJECT_ROOT=$(pwd)
DATA_DIR="$PROJECT_ROOT/data/pipeline"
IMAGES_DIR="$PROJECT_ROOT/images"

echo "Refreshing images from $DATA_DIR to $IMAGES_DIR..."

# 1. Create target directories
mkdir -p "$IMAGES_DIR/ci_evolution"
mkdir -p "$IMAGES_DIR/circuity_density"
mkdir -p "$IMAGES_DIR/cumulative_distance"
mkdir -p "$IMAGES_DIR/distance_comparison"
mkdir -p "$IMAGES_DIR/overline_maps"
mkdir -p "$IMAGES_DIR/od_hex_map"

# Helper function to copy and rename
# Usage: copy_plots "original_filename.png" "target_subdir"
copy_plots() {
    local pattern="$1"
    local subdir="$2"
    echo "  Refreshing images/$subdir/ (clearing old files first)"
    
    # Optional: Clear the subdirectory to avoid having both [city]_[file].png and [file]_[city].png
    rm -f "$IMAGES_DIR/$subdir"/*.png
    
    find "$DATA_DIR" -maxdepth 4 -name "$pattern" | while read -r filepath; do
        # Extract city name from data/pipeline/[city]/results/...
        city=$(echo "$filepath" | awk -F/ '{print $(NF-2)}')
        filename=$(basename "$filepath")
        
        # Copy and rename to [city]_[original_name]
        cp -f "$filepath" "$IMAGES_DIR/$subdir/${city}_${filename}"
    done
}

# 2. Execute copying for all requested patterns
copy_plots "plot_ci_types_absolute.png" "ci_evolution"
copy_plots "circuity_density_lts1.png" "circuity_density"
copy_plots "cumulative_distance_lts1.png" "cumulative_distance"
copy_plots "distance_comparison_16_26_lts1.png" "distance_comparison"
copy_plots "overline_map_lts1.png" "overline_maps"
copy_plots "overline_map_lts2.png" "overline_maps"
copy_plots "od_hex_map.png" "od_hex_map"

# 3. Ensure .gitignore is up to date
echo "Checking .gitignore entries..."
for entry in "images/ci_evolution" "images/circuity_density" "images/cumulative_distance" "images/distance_comparison" "images/overline_maps" "images/od_hex_map"; do
    if ! grep -q "^$entry" .gitignore 2>/dev/null; then
        echo "$entry" >> .gitignore
        echo "  Added $entry to .gitignore"
    fi
done

echo "Done! All plots have been collected and renamed in $IMAGES_DIR."
