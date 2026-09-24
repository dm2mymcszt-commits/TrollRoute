#!/bin/bash
set -euo pipefail
trap 'echo "Compatibility probe failed at line $LINENO: $BASH_COMMAND" >&2' ERR
cd "$(dirname "$0")/../.."
QA_DIR="$PWD/build/ios15-qa"
mkdir -p "$QA_DIR"
df -h
xcodebuild -version
curl --fail --location --retry 2 --max-time 60 \
  https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex \
  -o "$QA_DIR/catalog.plist"
SOURCE=$(python3 - "$QA_DIR" <<'PY'
import plistlib, pathlib, sys, json
root = pathlib.Path(sys.argv[1])
catalog = plistlib.loads((root / 'catalog.plist').read_bytes())
item = next(i for i in catalog['downloadables'] if i['identifier'] == 'com.apple.pkg.iPhoneSimulatorSDK15_5')
(root / 'runtime-source.json').write_text(json.dumps(item, indent=2))
assert item['source'].startswith('https://devimages-cdn.apple.com/downloads/xcode/simulators/')
print(item['source'])
PY
)
curl --fail --location --retry 2 --max-time 900 "$SOURCE" -o "$QA_DIR/runtime.dmg"
hdiutil attach -nobrowse -readonly -plist "$QA_DIR/runtime.dmg" > "$QA_DIR/mount.plist"
MOUNT=$(python3 -c 'import plistlib,sys; print(next(x["mount-point"] for x in plistlib.load(open(sys.argv[1],"rb"))["system-entities"] if "mount-point" in x))' "$QA_DIR/mount.plist")
PACKAGE=$(find "$MOUNT" -maxdepth 2 -name '*.pkg' -print -quit)
test -n "$PACKAGE"
# The legacy installer targets the sealed system volume. Install its unchanged
# runtime bundle in CoreSimulator's supported runtime directory instead.
pkgutil --expand-full "$PACKAGE" "$QA_DIR/expanded-runtime"
BUNDLE=$(find "$QA_DIR/expanded-runtime" -type d -name '*.simruntime' -print -quit)
# Component packages can install Payload itself as the runtime bundle (the
# .simruntime name lives in PackageInfo's install-location, not in Payload).
if [ -z "$BUNDLE" ]; then
  BUNDLE=$(python3 - "$QA_DIR/expanded-runtime" <<'PY'
from pathlib import Path
import sys, xml.etree.ElementTree as ET
root = Path(sys.argv[1])
for metadata in root.rglob('PackageInfo'):
    location = ET.parse(metadata).getroot().get('install-location', '')
    payload = metadata.parent / 'Payload'
    print(f'Component {metadata.name}: install-location={location}', file=sys.stderr)
    if location.endswith('.simruntime') and (payload / 'Contents/Info.plist').is_file():
        bundle = root / Path(location).name
        payload.rename(bundle)
        print(bundle)
        break
else:
    for path in sorted(root.rglob('*')):
        if len(path.relative_to(root).parts) <= 4:
            print(str(path.relative_to(root)), file=sys.stderr)
    for metadata in root.rglob('PackageInfo'):
        print(metadata.read_text(), file=sys.stderr)
    raise SystemExit('No complete runtime bundle in Apple package payload')
PY
)
fi
test -n "$BUNDLE"
sudo mkdir -p /Library/Developer/CoreSimulator/Profiles/Runtimes
sudo ditto "$BUNDLE" "/Library/Developer/CoreSimulator/Profiles/Runtimes/$(basename "$BUNDLE")"
hdiutil detach "$MOUNT"
xcrun simctl list runtimes -j > "$QA_DIR/runtimes.json"
python3 -c 'import json,sys; print([{k:r.get(k) for k in ("name","version","isAvailable","availabilityError")} for r in json.load(open(sys.argv[1]))["runtimes"] if r.get("version") == "15.5"])' "$QA_DIR/runtimes.json"
RUNTIME=$(python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(open(sys.argv[1]))["runtimes"] if r["isAvailable"] and r["version"] == "15.5"))' "$QA_DIR/runtimes.json")
DEVICE=$(xcrun simctl create TrollRoute15QA com.apple.CoreSimulator.SimDeviceType.iPhone-13 "$RUNTIME")
trap 'xcrun simctl shutdown "$DEVICE" || true; xcrun simctl delete "$DEVICE" || true' EXIT
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcodebuild -project TrollRoute.xcodeproj -scheme TrollRoute -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$QA_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO > "$QA_DIR/build.log" 2>&1 || { cat "$QA_DIR/build.log"; exit 1; }
xcrun simctl install "$DEVICE" "$QA_DIR/DerivedData/Build/Products/Debug-iphonesimulator/TrollRoute.app"
python3 Tests/MapWorkspace/ui-project.py "$QA_DIR" Tests/iOS15/LaunchTests.swift IOS15LaunchTests
xcodebuild test -project "$QA_DIR/IOS15LaunchTests.xcodeproj" -scheme IOS15LaunchTests \
  -destination "platform=iOS Simulator,id=$DEVICE" -parallel-testing-enabled NO \
  -derivedDataPath "$QA_DIR/TestDerivedData" -resultBundlePath "$QA_DIR/Launch.xcresult" \
  CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 > "$QA_DIR/tests.log" 2>&1 || {
    xcrun xcresulttool export attachments --path "$QA_DIR/Launch.xcresult" --output-path "$QA_DIR/attachments" || true
    cat "$QA_DIR/tests.log"; exit 1
  }
cat "$QA_DIR/tests.log"
xcrun xcresulttool export attachments --path "$QA_DIR/Launch.xcresult" --output-path "$QA_DIR/attachments"
