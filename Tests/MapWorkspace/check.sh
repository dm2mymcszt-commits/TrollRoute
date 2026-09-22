#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QA_DIR="$PWD/build/map-workspace-qa"
mkdir -p "$QA_DIR"
python3 - "$QA_DIR/AppSettings.swift" <<'PY'
from pathlib import Path
import sys
source = Path('TrollRoute/TrollRouteApp.swift').read_text()
models = source.split('class AppSettings: ObservableObject {')[1]
Path(sys.argv[1]).write_text('import SwiftUI\nclass AppSettings: ObservableObject {' + models)
content = Path('TrollRoute/ContentView.swift').read_text()
assert 'TabView' not in content and 'LocSimView()' in content
project = Path('TrollRoute.xcodeproj/project.pbxproj').read_text()
for removed in ['HomeView.swift', 'DaemonView.swift', 'CleanerView.swift', 'SuperviseView.swift', 'ByeTimeView.swift']:
    assert removed not in project, f'{removed} remains in the build'
print('PASS: full-screen map entry and unused feature sources removed from the build')
PY
python3 Tests/MapWorkspace/prepare.py "$QA_DIR"
PREVIEW_APP="$QA_DIR/MapWorkspacePreview.app"
mkdir -p "$PREVIEW_APP"
python3 Tests/RoutePicker/bookmark-support.py "$QA_DIR/Bookmarks.swift"
xcrun --sdk iphonesimulator swiftc TrollRoute/Storage/SharedPreferences.swift TrollRoute/Storage/FavoritesStore.swift -target arm64-apple-ios17.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  "$QA_DIR/CustomMapView.swift" TrollRoute/LocSim/FloatingQuickMenu.swift \
  TrollRoute/LocSim/RouteLocationPicker.swift TrollRoute/LocSim/FavoritePlaceEditor.swift TrollRoute/LocSim/PlaceModels.swift TrollRoute/LocSim/PlaceInput.swift TrollRoute/LocSim/AddressQuery.swift TrollRoute/LocSim/PlaceSearch.swift TrollRoute/SettingsView.swift \
  TrollRoute/LocSim/MapMoveConfirmation.swift TrollRoute/LocSim/MainStopConfirmation.swift "$QA_DIR/LongPressRoute.swift" \
  TrollRoute/LocSim/RouteElevation.swift TrollRoute/LocSim/Altitude.swift TrollRoute/LocSim/AltitudeSheet.swift \
  TrollRoute/LocSim/CoordTransform.swift TrollRoute/LocSim/RouteFinish.swift TrollRoute/LocSim/RouteStop.swift TrollRoute/LocSim/LocationSession.swift "$QA_DIR/Bookmarks.swift" \
  TrollRoute/LocSim/SharedPlace.swift "$QA_DIR/AppSettings.swift" Tests/MapWorkspace/Preview.swift \
  -o "$PREVIEW_APP/MapWorkspacePreview"
python3 - "$PREVIEW_APP/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='local.trollroute.workspacepreview',
        CFBundleExecutable='MapWorkspacePreview', CFBundleName='MapWorkspacePreview',
        CFBundleShortVersionString='2.6.0', CFBundleVersion='4',
        CFBundlePackageType='APPL', MinimumOSVersion='17.0', UIDeviceFamily=[1],
        UILaunchScreen={}, NSLocationWhenInUseUsageDescription='Preview the map.'), f)
PY
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and "iOS" in r["name"]))')
DEVICE=$(xcrun simctl create MapWorkspaceQA com.apple.CoreSimulator.SimDeviceType.iPhone-12 "$RUNTIME")
trap 'xcrun simctl shutdown "$DEVICE" || true; xcrun simctl delete "$DEVICE" || true' EXIT
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl install "$DEVICE" "$PREVIEW_APP"
python3 Tests/MapWorkspace/ui-project.py "$QA_DIR"
xcodebuild test -project "$QA_DIR/MapGestureTests.xcodeproj" -scheme MapGestureTests \
  -destination "platform=iOS Simulator,id=$DEVICE" -parallel-testing-enabled NO \
  -derivedDataPath "$QA_DIR/DerivedData" -resultBundlePath "$QA_DIR/Gestures.xcresult" \
  CODE_SIGNING_ALLOWED=NO > "$QA_DIR/gestures.log" 2>&1 || {
    xcrun xcresulttool export attachments --path "$QA_DIR/Gestures.xcresult" --output-path "$QA_DIR/attachments" || true
    cat "$QA_DIR/gestures.log"
    exit 1
  }
cat "$QA_DIR/gestures.log"
xcrun xcresulttool export attachments --path "$QA_DIR/Gestures.xcresult" --output-path "$QA_DIR/attachments"
for appearance in dark light; do
  xcrun simctl ui "$DEVICE" appearance "$appearance"
  for screen in map settings settings-enabled confirmation search altitude-automatic altitude-custom altitude-negative; do
    xcrun simctl terminate "$DEVICE" local.trollroute.workspacepreview 2>/dev/null || true
    xcrun simctl launch "$DEVICE" local.trollroute.workspacepreview --screen "$screen" --appearance "$appearance"
    if test "$screen" = search; then sleep 20; else sleep 5; fi
    xcrun simctl io "$DEVICE" screenshot "$QA_DIR/$screen-$appearance.png"
  done
done
