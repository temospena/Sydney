#!/bin/bash
# build_brouter_segments.sh
# Combines per-city OSM PBF files into a master PBF per year, then generates BRouter segments
# Ensure brouter mapcreator jar exists in data/brouter/brouter_bin/ before running this.

set -e

mkdir -p data/brouter/{segments_2016,segments_2021,segments_2026,brouter_bin}
mkdir -p data/brouter/custom_profiles

JAVA='java -Xmx8G -Xms8G -Xmn256M'

BROUTER_JAR="data/brouter/brouter_bin/brouter-server-1.7.8-all.jar"
if [ ! -f "$BROUTER_JAR" ]; then
    echo "ERROR: BRouter mapcreator jar not found at $BROUTER_JAR"
    exit 1
fi

BROUTER_PROFILES="data/brouter/brouter_bin/profiles2"
if [ ! -d "$BROUTER_PROFILES" ]; then
    wget -qO /tmp/br.zip https://github.com/abrensch/brouter/releases/download/v1.7.8/brouter-1.7.8.zip
    unzip -q /tmp/br.zip -d data/brouter/brouter_bin/
    mv data/brouter/brouter_bin/brouter-1.7.8/profiles2 data/brouter/brouter_bin/ || true
    rm /tmp/br.zip
fi

YEARS=("16" "21" "26")
V_YEARS=("2016" "2021" "2026")

for i in "${!YEARS[@]}"; do
    yr="${YEARS[$i]}"
    v_yr="${V_YEARS[$i]}"
    
    echo "------------------------------------------------"
    echo "Processing $v_yr..."
    echo "------------------------------------------------"
    
    pbf_files=()
    for dir in data/pipeline/*/; do
        if [ -d "$dir" ]; then
            city_name=$(basename "$dir")
            pbf="data/pipeline/${city_name}/${city_name}_${yr}.osm.pbf"
            if [ -f "$pbf" ]; then
                pbf_files+=("$pbf")
            fi
        fi
    done
    
    if [ ${#pbf_files[@]} -eq 0 ]; then
        echo "No PBF files found for year $yr"
        continue
    fi
    
    PLANET_FILE="data/brouter/master_${v_yr}.osm.pbf"
    echo "Merging ${#pbf_files[@]} files into $PLANET_FILE..."
    osmium merge "${pbf_files[@]}" -o "$PLANET_FILE" --overwrite
    
    echo "Extracting BRouter RD5 segments for $v_yr (3-step FastMapCreator process)..."
    
    mkdir -p tmp_${v_yr}
    pushd tmp_${v_yr} > /dev/null
    
    LOCAL_PROFILES="../$BROUTER_PROFILES"
    LOCAL_PLANET="../$PLANET_FILE"
    
    mkdir -p srtm
    mkdir -p nodetiles waytiles waytiles55 nodes55
    
    echo "Step 1: OsmFastCutter"
    ${JAVA} -cp ../${BROUTER_JAR} -DavoidMapPolling=true -Ddeletetmpfiles=true -DuseDenseMaps=true btools.mapcreator.OsmFastCutter ${LOCAL_PROFILES}/lookups.dat nodetiles waytiles nodes55 waytiles55 bordernids.dat relations.dat restrictions.dat ${LOCAL_PROFILES}/all.brf ${LOCAL_PROFILES}/trekking.brf ${LOCAL_PROFILES}/softaccess.brf ${LOCAL_PLANET}
    
    echo "Step 2: PosUnifier"
    mkdir -p unodes55
    ${JAVA} -cp ../${BROUTER_JAR} -Ddeletetmpfiles=true -DuseDenseMaps=true btools.mapcreator.PosUnifier nodes55 unodes55 bordernids.dat bordernodes.dat srtm srtm
    
    echo "Step 3: WayLinker (Creating RD5 files)"
    mkdir -p segments
    ${JAVA} -cp ../${BROUTER_JAR} -DuseDenseMaps=true -DskipEncodingCheck=true btools.mapcreator.WayLinker unodes55 waytiles55 bordernodes.dat restrictions.dat ${LOCAL_PROFILES}/lookups.dat ${LOCAL_PROFILES}/all.brf segments rd5
    
    popd > /dev/null
    
    echo "Cleaning up intermediate files for $v_yr..."
    rm -rf data/brouter/segments_${v_yr}
    mv tmp_${v_yr}/segments data/brouter/segments_${v_yr}
    rm -rf tmp_${v_yr}
    rm -f "$PLANET_FILE"
    
    echo "Segments for $v_yr created in data/brouter/segments_${v_yr}/"
done

echo "BRouter segments build completed."
