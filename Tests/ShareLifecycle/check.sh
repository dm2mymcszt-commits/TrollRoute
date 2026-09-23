#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QA_DIR="$PWD/build/share-lifecycle-qa"
python3 Tests/ShareLifecycle/prepare.py "$QA_DIR"
APP="$QA_DIR/ShareLifecycle.app"
COMMON=(TrollRoute/Storage/SharedPreferences.swift TrollRoute/Storage/FavoritesStore.swift
  TrollRoute/LocSim/PlaceModels.swift TrollRoute/LocSim/PlaceInput.swift
  TrollRoute/LocSim/AddressQuery.swift TrollRoute/LocSim/PlaceSearch.swift TrollRoute/LocSim/CoordTransform.swift)
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" "${COMMON[@]}" \
  TrollRoute/LocSim/RouteSimulator.swift TrollRoute/LiveActivity/RouteActivityState.swift TrollRoute/LocSim/LocationSession.swift \
  TrollRoute/LocSim/RouteFinish.swift TrollRoute/LocSim/RouteStop.swift \
  TrollRoute/LocSim/RouteElevation.swift TrollRoute/LocSim/Altitude.swift TrollRoute/LocSim/AltitudeSheet.swift \
  TrollRoute/LocSim/RouteFinishControls.swift TrollRoute/LocSim/RouteStopDialog.swift \
  TrollRoute/LocSim/CustomMapView.swift TrollRoute/LocSim/FloatingQuickMenu.swift \
  TrollRoute/LocSim/MapMoveConfirmation.swift TrollRoute/LocSim/MainStopConfirmation.swift \
  TrollRoute/LocSim/LongPressRoute.swift TrollRoute/LocSim/GPXParser.swift TrollRoute/LocSim/JoystickView.swift \
  TrollRoute/LocSim/RouteLocationPicker.swift TrollRoute/LocSim/FavoritePlaceEditor.swift TrollRoute/SettingsView.swift TrollRoute/LocationAccess.swift \
  "$QA_DIR/RouteLocationSample.swift" "$QA_DIR/EngineFixture.swift" "$QA_DIR/Bookmarks.swift" \
  "$QA_DIR/SharedPlace.swift" "$QA_DIR/SharePlaceView.swift" "$QA_DIR/LocSimView.swift" \
  "$QA_DIR/RouteSimView.swift" "$QA_DIR/FavoritesView.swift" Tests/ShareLifecycle/Host.swift \
  -o "$APP/ShareLifecycle"
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and "iOS" in r["name"]))')
DEVICE=$(xcrun simctl create ShareLifecycleQA com.apple.CoreSimulator.SimDeviceType.iPhone-12 "$RUNTIME")
trap 'xcrun simctl shutdown "$DEVICE" || true; xcrun simctl delete "$DEVICE" || true' EXIT
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl ui "$DEVICE" appearance dark
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl privacy "$DEVICE" grant location-always local.trollroute.sharelifecycle
python3 Tests/MapWorkspace/ui-project.py "$QA_DIR" Tests/ShareLifecycle/LifecycleTests.swift ShareLifecycleTests \
  "${COMMON[@]}" TrollRoute/LocSim/SharedPlace.swift
xcodebuild test -project "$QA_DIR/ShareLifecycleTests.xcodeproj" -scheme ShareLifecycleTests \
  -destination "platform=iOS Simulator,id=$DEVICE" -parallel-testing-enabled NO \
  -derivedDataPath "$QA_DIR/DerivedData" -resultBundlePath "$QA_DIR/Lifecycle.xcresult" \
  CODE_SIGNING_ALLOWED=NO > "$QA_DIR/tests.log" 2>&1 || {
    xcrun xcresulttool export attachments --path "$QA_DIR/Lifecycle.xcresult" --output-path "$QA_DIR/attachments" || true
    cat "$QA_DIR/tests.log"
    exit 1
  }
cat "$QA_DIR/tests.log"
xcrun xcresulttool export attachments --path "$QA_DIR/Lifecycle.xcresult" --output-path "$QA_DIR/attachments"
