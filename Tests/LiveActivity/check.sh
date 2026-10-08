#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QA_DIR="${ACTIVITY_QA_DIR:-$PWD/build/live-activity-qa}"
mkdir -p "$QA_DIR"
source Tests/LiveActivity/methods.sh
: > "$QA_DIR/failed-methods.txt"
python3 Tests/LiveActivity/prepare.py "$QA_DIR"
xcodebuild -project "$QA_DIR/LiveActivityQA.xcodeproj" -target LiveActivityQA -configuration Debug \
  -sdk iphonesimulator SYMROOT="$QA_DIR/Products" OBJROOT="$QA_DIR/Objects" \
  CODE_SIGNING_ALLOWED=NO > "$QA_DIR/build.log" 2>&1 || { cat "$QA_DIR/build.log"; exit 1; }
xcodebuild -project "$QA_DIR/LiveActivityQA.xcodeproj" -target CompanionQA -configuration Debug \
  -sdk iphonesimulator SYMROOT="$QA_DIR/Products" OBJROOT="$QA_DIR/Objects" \
  CODE_SIGNING_ALLOWED=NO >> "$QA_DIR/build.log" 2>&1 || { cat "$QA_DIR/build.log"; exit 1; }
xcrun simctl list runtimes -j > "$QA_DIR/runtimes.json"
RUNTIME=$(python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(open(sys.argv[1]))["runtimes"] if r["isAvailable"] and "iOS" in r["name"]))' "$QA_DIR/runtimes.json")
DEVICE=""
CASE_DIR="$QA_DIR"
finish() {
  if [ -z "$DEVICE" ]; then return; fi
  # Keep renderer failures, including extension crashes, separate from XCTest
  # assertions about missing controls. Logs come from this test's simulator.
  xcrun simctl spawn "$DEVICE" log show --last 15m --style compact --info --debug \
    --predicate 'process == "TrollRouteActivity" OR process == "chronod" OR process == "liveactivitiesd"' \
    > "$CASE_DIR/activity-system.log" 2>&1 || true
  mkdir -p "$CASE_DIR/crashes"
  find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'TrollRouteActivity*' \
    -exec cp {} "$CASE_DIR/crashes/" \; 2>/dev/null || true
  xcrun simctl shutdown "$DEVICE" || true
  xcrun simctl delete "$DEVICE" || true
  DEVICE=""
}
trap finish EXIT
python3 Tests/MapWorkspace/ui-project.py "$QA_DIR" Tests/LiveActivity/SystemTests.swift LiveActivityTests \
  Tests/LiveActivity/ControlGeometry.swift
# A failed companion End or locked SpringBoard must never contaminate another
# scenario. Each original test runs, with all its assertions, on a fresh device.
failed=0
for method in "${methods[@]}"; do
CASE_DIR="$QA_DIR/$method"
mkdir -p "$CASE_DIR"
echo "Live Activity $method: creating and booting a fresh simulator"
DEVICE=$(xcrun simctl create LiveActivityQA com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro "$RUNTIME")
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl ui "$DEVICE" appearance "${ACTIVITY_APPEARANCE:-dark}"
xcrun simctl install "$DEVICE" "$QA_DIR/Products/Debug-iphonesimulator/LiveActivityQA.app"
xcrun simctl install "$DEVICE" "$QA_DIR/Products/Debug-iphonesimulator/CompanionQA.app"
xcrun simctl privacy "$DEVICE" grant location local.trollroute.activityqa
echo "Live Activity $method: running all scenario assertions"
if xcodebuild test -project "$QA_DIR/LiveActivityTests.xcodeproj" -scheme LiveActivityTests \
  -destination "platform=iOS Simulator,id=$DEVICE" -parallel-testing-enabled NO \
  -only-testing:"LiveActivityTests/LiveActivitySystemTests/$method" \
  -derivedDataPath "$QA_DIR/TestDerivedData" -resultBundlePath "$CASE_DIR/System.xcresult" \
  CODE_SIGNING_ALLOWED=NO > "$CASE_DIR/tests.log" 2>&1; then
  # xcodebuild can exit successfully when a misspelled test filter ran nothing.
  python3 - "$CASE_DIR/tests.log" "$method" <<'PY'
import re, sys
from pathlib import Path
log = Path(sys.argv[1]).read_text()
assert re.search(r"Test Case .* " + re.escape(sys.argv[2]) + r"\]' passed", log), 'Required test did not pass'
PY
else
  if ! grep -q 'Test Suite .* started' "$CASE_DIR/tests.log"; then
    cat "$CASE_DIR/tests.log"
    exit 1
  fi
  failed=1
  printf '%s\n' "$method" >> "$QA_DIR/failed-methods.txt"
fi
cat "$CASE_DIR/tests.log"
echo "Live Activity $method: exporting attachments and system diagnostics"
xcrun xcresulttool export attachments --path "$CASE_DIR/System.xcresult" --output-path "$CASE_DIR/attachments" || true
finish
echo "Live Activity $method: scenario and cleanup complete"
done
# Distinguish an executed UI failure from a build/setup failure. Only the former
# is eligible for the bounded clean-environment retry in run.sh.
if [ "$failed" -ne 0 ]; then exit 2; fi
