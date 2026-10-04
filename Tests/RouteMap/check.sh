#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QA_DIR="$PWD/build/route-map-qa"
mkdir -p "$QA_DIR"

# Compile the actual production map and card, without the simulator's privileged helper.
python3 - "$QA_DIR/RouteChoiceCard.swift" <<'PY'
from pathlib import Path
import sys
source = Path('TrollRoute/LocSim/RouteSimView.swift').read_text()
marker = 'struct RouteModeControls: View {'
if source.count(marker) != 1:
    raise SystemExit('Expected exactly one production RouteChoiceCard')
Path(sys.argv[1]).write_text('import SwiftUI\n' + marker + source.split(marker, 1)[1])
models = Path('TrollRoute/LocSim/RouteSimulator.swift').read_text().split('class RouteSimulator: NSObject')[0]
Path(sys.argv[1]).with_name('RouteModels.swift').write_text(models)
PY
PREVIEW_APP="$QA_DIR/RouteMapPreview.app"
mkdir -p "$PREVIEW_APP"
xcrun --sdk iphonesimulator swiftc TrollRoute/LocSim/Flight.swift TrollRoute/LocSim/RouteHistory.swift TrollRoute/Storage/SharedPreferences.swift -target arm64-apple-ios17.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  TrollRoute/LocSim/CustomMapView.swift TrollRoute/LocSim/CoordTransform.swift TrollRoute/LocSim/RouteFinish.swift TrollRoute/LocSim/FloatingQuickMenu.swift "$QA_DIR/RouteChoiceCard.swift" "$QA_DIR/RouteModels.swift" Tests/RouteMap/Preview.swift \
  -o "$PREVIEW_APP/RouteMapPreview"
python3 - "$PREVIEW_APP/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='local.trollroute.routemappreview',
        CFBundleExecutable='RouteMapPreview', CFBundleName='RouteMapPreview',
        CFBundlePackageType='APPL', MinimumOSVersion='17.0', UIDeviceFamily=[1],
        UILaunchScreen={}, NSLocationWhenInUseUsageDescription='Preview the map.'), f)
PY
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and "iOS" in r["name"]))')
DEVICE=$(xcrun simctl create RouteMapQA com.apple.CoreSimulator.SimDeviceType.iPhone-12 "$RUNTIME")
trap 'xcrun simctl shutdown "$DEVICE" || true; xcrun simctl delete "$DEVICE" || true' EXIT
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$DEVICE" "$PREVIEW_APP"
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" local.trollroute.routemappreview data)

for appearance in dark light; do
  xcrun simctl ui "$DEVICE" appearance "$appearance"
  for section in map cards modes playback collapsed; do
    # A separate launch controls scroll position deterministically, with no UI automation dependency.
    xcrun simctl terminate "$DEVICE" local.trollroute.routemappreview 2>/dev/null || true
    RESULT="$CONTAINER/Documents/route-map-$appearance-$section.txt"
    rm -f "$RESULT"
    xcrun simctl launch --stdout="$QA_DIR/$appearance-$section-stdout.log" \
      --stderr="$QA_DIR/$appearance-$section-stderr.log" "$DEVICE" local.trollroute.routemappreview --appearance "$appearance" --section "$section"
    ready=false
    for attempt in $(seq 1 40); do
      if test -s "$RESULT"; then ready=true; break; fi
      sleep 1
    done
    if test "$ready" != true; then
      echo "Route map preview did not report completion ($appearance/$section)."
      cat "$QA_DIR/$appearance-$section-stdout.log" "$QA_DIR/$appearance-$section-stderr.log"
      exit 1
    fi
    cat "$RESULT"
    cp "$RESULT" "$QA_DIR/route-map-$appearance-$section.txt"
    python3 - "$RESULT" <<'PY'
from pathlib import Path
import sys
result = Path(sys.argv[1]).read_text()
if not result.startswith('PASS:'):
    raise SystemExit(result)
PY
    xcrun simctl io "$DEVICE" screenshot "$QA_DIR/route-map-$appearance-$section.png"
  done
done
