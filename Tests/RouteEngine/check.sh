#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QA_DIR="$PWD/build/route-engine-qa"
PREVIEW_APP="$QA_DIR/RouteEngineTests.app"
mkdir -p "$PREVIEW_APP"
python3 - "$QA_DIR/RouteLocationSample.swift" "$PREVIEW_APP/Info.plist" <<'PY'
from pathlib import Path
import plistlib, sys
source = Path('TrollRoute/LocSim/LocSimManager.swift').read_text()
Path(sys.argv[1]).write_text(source.split('class LocSimManager {')[0])
with open(sys.argv[2], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='local.trollroute.enginetests',
        CFBundleExecutable='RouteEngineTests', CFBundleName='RouteEngineTests',
        CFBundlePackageType='APPL', MinimumOSVersion='17.0', UIDeviceFamily=[1],
        UILaunchScreen={}, UIBackgroundModes=['location'],
        NSLocationWhenInUseUsageDescription='Exercise route lifecycle.',
        NSLocationAlwaysAndWhenInUseUsageDescription='Exercise route lifecycle.'), f)
PY
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  TrollRoute/Storage/SharedPreferences.swift TrollRoute/LocSim/RouteSimulator.swift TrollRoute/LiveActivity/RouteActivityState.swift TrollRoute/LocationAccess.swift \
  TrollRoute/LocSim/RouteFinish.swift TrollRoute/LocSim/RouteStop.swift TrollRoute/LocSim/CoordTransform.swift \
  TrollRoute/LocSim/RouteElevation.swift TrollRoute/LocSim/Altitude.swift \
  TrollRoute/LocSim/LocationSession.swift "$QA_DIR/RouteLocationSample.swift" \
  Tests/RouteEngine/EngineTests.swift -o "$PREVIEW_APP/RouteEngineTests"
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and "iOS" in r["name"]))')
DEVICE=$(xcrun simctl create RouteEngineQA com.apple.CoreSimulator.SimDeviceType.iPhone-12 "$RUNTIME")
trap 'xcrun simctl shutdown "$DEVICE" || true; xcrun simctl delete "$DEVICE" || true' EXIT
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$PREVIEW_APP"
xcrun simctl privacy "$DEVICE" grant location local.trollroute.enginetests
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" local.trollroute.enginetests data)
xcrun simctl launch --stdout="$QA_DIR/stdout.log" --stderr="$QA_DIR/stderr.log" "$DEVICE" local.trollroute.enginetests
for attempt in $(seq 1 30); do
  if test -f "$CONTAINER/Documents/results.txt"; then
    cp "$CONTAINER/Documents/results.txt" "$QA_DIR/results.txt"
    cat "$QA_DIR/results.txt"
    exit 0
  fi
  sleep 1
done
cat "$QA_DIR/stdout.log" "$QA_DIR/stderr.log"
echo 'FAIL: actual route engine did not complete its assertions'
exit 1
