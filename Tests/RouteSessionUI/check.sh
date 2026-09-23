#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QA_DIR="$PWD/build/route-session-ui"
PREVIEW_APP="$QA_DIR/RouteSessionUI.app"
mkdir -p "$PREVIEW_APP"
python3 - "$QA_DIR" <<'PY'
from pathlib import Path
import plistlib, sys
out = Path(sys.argv[1])
sample = Path('TrollRoute/LocSim/LocSimManager.swift').read_text().split('class LocSimManager {')[0]
(out / 'RouteLocationSample.swift').write_text(sample)
fixture = Path('Tests/RouteEngine/EngineTests.swift').read_text().split('@main final class EngineApp')[0]
(out / 'EngineFixture.swift').write_text(fixture)
view = Path('TrollRoute/LocSim/RouteSimView.swift').read_text()
assert view.count('import AlertKit') == 1 and view.count('AlertKitAPI.present(') == 2
# The success toasts are decorative. Compile every production view and action,
# including RouteSimSheet.startRoute, without this unrelated package dependency.
view = '\n'.join(line for line in view.splitlines()
                 if line != 'import AlertKit' and 'AlertKitAPI.present(' not in line)
(out / 'RouteSimView.swift').write_text(view)
with (out / 'RouteSessionUI.app/Info.plist').open('wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='local.trollroute.sessionui',
        CFBundleExecutable='RouteSessionUI', CFBundleName='RouteSessionUI',
        CFBundlePackageType='APPL', MinimumOSVersion='17.0', UIDeviceFamily=[1],
        UILaunchScreen={}, UIBackgroundModes=['location'],
        NSLocationWhenInUseUsageDescription='Exercise route controls.',
        NSLocationAlwaysAndWhenInUseUsageDescription='Exercise route controls.'), f)
PY
python3 Tests/RoutePicker/bookmark-support.py "$QA_DIR/Bookmarks.swift"
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  TrollRoute/Storage/SharedPreferences.swift TrollRoute/Storage/FavoritesStore.swift TrollRoute/LocSim/RouteSimulator.swift TrollRoute/LiveActivity/RouteActivityState.swift TrollRoute/LocationAccess.swift \
  TrollRoute/LocSim/RouteFinish.swift TrollRoute/LocSim/RouteStop.swift TrollRoute/LocSim/CoordTransform.swift \
  TrollRoute/LocSim/RouteElevation.swift TrollRoute/LocSim/Altitude.swift TrollRoute/LocSim/LocationSession.swift \
  TrollRoute/LocSim/RouteFinishControls.swift TrollRoute/LocSim/RouteStopDialog.swift \
  TrollRoute/LocSim/CustomMapView.swift TrollRoute/LocSim/FloatingQuickMenu.swift \
  TrollRoute/LocSim/GPXParser.swift TrollRoute/LocSim/SharedPlace.swift TrollRoute/LocSim/LongPressRoute.swift \
  TrollRoute/LocSim/RouteLocationPicker.swift TrollRoute/LocSim/FavoritePlaceEditor.swift \
  TrollRoute/LocSim/PlaceModels.swift TrollRoute/LocSim/PlaceInput.swift TrollRoute/LocSim/AddressQuery.swift TrollRoute/LocSim/PlaceSearch.swift \
  "$QA_DIR/RouteLocationSample.swift" "$QA_DIR/RouteSimView.swift" "$QA_DIR/EngineFixture.swift" \
  "$QA_DIR/Bookmarks.swift" Tests/RouteSessionUI/Host.swift -o "$PREVIEW_APP/RouteSessionUI"
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and "iOS" in r["name"]))')
DEVICE=$(xcrun simctl create RouteSessionUI com.apple.CoreSimulator.SimDeviceType.iPhone-12 "$RUNTIME")
trap 'xcrun simctl shutdown "$DEVICE" || true; xcrun simctl delete "$DEVICE" || true' EXIT
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl ui "$DEVICE" appearance dark
xcrun simctl install "$DEVICE" "$PREVIEW_APP"
xcrun simctl privacy "$DEVICE" grant location-always local.trollroute.sessionui
python3 Tests/MapWorkspace/ui-project.py "$QA_DIR" Tests/RouteSessionUI/SessionTests.swift RouteSessionTests
xcodebuild test -project "$QA_DIR/RouteSessionTests.xcodeproj" -scheme RouteSessionTests \
  -destination "platform=iOS Simulator,id=$DEVICE" -parallel-testing-enabled NO \
  -derivedDataPath "$QA_DIR/DerivedData" -resultBundlePath "$QA_DIR/Session.xcresult" \
  CODE_SIGNING_ALLOWED=NO > "$QA_DIR/tests.log" 2>&1 || {
    xcrun xcresulttool export attachments --path "$QA_DIR/Session.xcresult" --output-path "$QA_DIR/attachments" || true
    cat "$QA_DIR/tests.log"
    exit 1
  }
cat "$QA_DIR/tests.log"
xcrun xcresulttool export attachments --path "$QA_DIR/Session.xcresult" --output-path "$QA_DIR/attachments"
