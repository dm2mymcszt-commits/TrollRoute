#!/bin/bash
set -euo pipefail
out=build/rail-audit
mkdir -p "$out"
source_name=france-261003.osm.pbf
source_url="https://download.geofabrik.de/europe/$source_name"
agent='TrollRoute/3.1-feasibility (+https://github.com/dm2mymcszt-commits/TrollRoute)'
# One sequential extract download for this audit, not an application endpoint.
curl --fail --location --retry 2 --retry-delay 30 --user-agent "$agent" \
  "$source_url.md5" --output "$out/source-md5.txt"
curl --fail --location --retry 2 --retry-delay 30 --user-agent "$agent" \
  "$source_url" --output "$out/$source_name"
expected=$(awk '{print $1}' "$out/source-md5.txt")
printf '%s  %s\n' "$expected" "$out/$source_name" | md5sum --check
stat -c %s "$out/$source_name" > "$out/source-bytes.txt"
sha256sum "$out/$source_name" > "$out/source-sha256.txt"
# Keep referenced geometry. Station relations are retained as station metadata,
# never used as a substitute for the physical rail graph.
/usr/bin/time -v -o "$out/filter-resource.txt" osmium tags-filter \
  "$out/$source_name" 'w/railway=rail,narrow_gauge,light_rail' \
  'nwr/railway=station,halt' -t -o "$out/rails.osm.pbf"
/usr/bin/time -v -o "$out/graph-resource.txt" /usr/bin/python3 Tools/RailAudit/measure.py \
  "$out/rails.osm.pbf" "$out/rail.sqlite" "$out/metrics.json"
cat "$out/metrics.json"
cat "$out/metrics.json" >> "$GITHUB_STEP_SUMMARY"
