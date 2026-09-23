#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QA_DIR="$PWD/build/live-activity-qa"
mkdir -p "$QA_DIR"
python3 Tests/LiveActivity/prepare.py "$QA_DIR"
xcodebuild -project "$QA_DIR/LiveActivityQA.xcodeproj" -target LiveActivityQA -configuration Debug \
  -sdk iphonesimulator SYMROOT="$QA_DIR/Products" OBJROOT="$QA_DIR/Objects" \
  CODE_SIGNING_ALLOWED=NO > "$QA_DIR/build.log" 2>&1 || { cat "$QA_DIR/build.log"; exit 1; }
xcrun simctl list runtimes -j > "$QA_DIR/runtimes.json"
RUNTIME=$(python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(open(sys.argv[1]))["runtimes"] if r["isAvailable"] and "iOS" in r["name"]))' "$QA_DIR/runtimes.json")
DEVICE=$(xcrun simctl create LiveActivityQA com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro "$RUNTIME")
trap 'xcrun simctl shutdown "$DEVICE" || true; xcrun simctl delete "$DEVICE" || true' EXIT
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl ui "$DEVICE" appearance dark
xcrun simctl install "$DEVICE" "$QA_DIR/Products/Debug-iphonesimulator/LiveActivityQA.app"
xcrun simctl privacy "$DEVICE" grant location local.trollroute.activityqa
python3 Tests/MapWorkspace/ui-project.py "$QA_DIR" Tests/LiveActivity/SystemTests.swift LiveActivityTests
xcodebuild test -project "$QA_DIR/LiveActivityTests.xcodeproj" -scheme LiveActivityTests \
  -destination "platform=iOS Simulator,id=$DEVICE" -parallel-testing-enabled NO \
  -derivedDataPath "$QA_DIR/TestDerivedData" -resultBundlePath "$QA_DIR/System.xcresult" \
  CODE_SIGNING_ALLOWED=NO > "$QA_DIR/tests.log" 2>&1 || {
    xcrun xcresulttool export attachments --path "$QA_DIR/System.xcresult" --output-path "$QA_DIR/attachments" || true
    cat "$QA_DIR/tests.log"; exit 1
  }
cat "$QA_DIR/tests.log"
xcrun xcresulttool export attachments --path "$QA_DIR/System.xcresult" --output-path "$QA_DIR/attachments"
