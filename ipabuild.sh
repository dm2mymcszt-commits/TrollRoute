#!/bin/bash

set -e

cd "$(dirname "$0")"

WORKING_LOCATION="$(pwd)"
APPLICATION_NAME=TrollRoute
CONFIGURATION=Debug

rm -rf build
if [ ! -d "build" ]; then
    mkdir build
fi

cd build

if [ -e "$APPLICATION_NAME.tipa" ]; then
rm $APPLICATION_NAME.tipa
fi

# Build .app
xcodebuild -project "$WORKING_LOCATION/$APPLICATION_NAME.xcodeproj" \
    -scheme TrollRoute \
    -configuration Debug \
    -derivedDataPath "$WORKING_LOCATION/build/DerivedData" \
    -destination 'generic/platform=iOS' \
    ONLY_ACTIVE_ARCH="NO" \
    CODE_SIGNING_ALLOWED="NO" \
    ENABLE_DEBUG_DYLIB="NO"
    
DD_APP_PATH="$WORKING_LOCATION/build/DerivedData/Build/Products/$CONFIGURATION-iphoneos/$APPLICATION_NAME.app"
TARGET_APP="$WORKING_LOCATION/build/$APPLICATION_NAME.app"
cp -r "$DD_APP_PATH" "$TARGET_APP"

# Remove signature
if codesign --display "$TARGET_APP" 2>/dev/null; then
    codesign --remove-signature "$TARGET_APP"
fi
if [ -e "$TARGET_APP/_CodeSignature" ]; then
    rm -rf "$TARGET_APP/_CodeSignature"
fi
if [ -e "$TARGET_APP/embedded.mobileprovision" ]; then
    rm -rf "$TARGET_APP/embedded.mobileprovision"
fi

# Is ldid installed ?
if command -v ldid &> /dev/null; then
    echo "ldid is already installed."
else
    # Install ldid using Homebrew
    if command -v brew &> /dev/null; then
        echo "Installing ldid with Homebrew..."
        brew install ldid
        echo "ldid has been installed."
    else
        echo "Homebrew is not installed. Please install Homebrew first."
    fi
fi

# Add entitlements
echo "Adding entitlements"
ldid -S"$WORKING_LOCATION/entitlements.plist" "$TARGET_APP/$APPLICATION_NAME"
# Sign the share extension
ldid -S"$WORKING_LOCATION/TrollRouteShare/entitlements.plist" "$TARGET_APP/PlugIns/TrollRouteShare.appex/TrollRouteShare"
ldid -S"$WORKING_LOCATION/TrollRouteActivity/entitlements.plist" "$TARGET_APP/PlugIns/TrollRouteActivity.appex/TrollRouteActivity"

# Package .ipa
rm -rf Payload
mkdir Payload
cp -r $APPLICATION_NAME.app Payload/$APPLICATION_NAME.app
zip -vr $APPLICATION_NAME.tipa Payload
rm -rf $APPLICATION_NAME.app
rm -rf Payload
