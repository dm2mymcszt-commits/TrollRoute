#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QA_DIR="$PWD/build/keeper-qa"
mkdir -p "$QA_DIR"
xcrun clang -std=c11 -Wall -Wextra -Werror Tests/Keeper/protection.c -o "$QA_DIR/protection-tests"
"$QA_DIR/protection-tests"
xcrun swiftc -parse-as-library TrollRoute/Storage/SharedPreferences.swift \
  TrollRoute/LocSim/RouteElevation.swift TrollRoute/LocSim/Altitude.swift \
  TrollRoute/LocSim/LocationSession.swift TrollRoute/LocSim/LocSimManager.swift \
  TrollRoute/Keeper/Keeper.swift Tests/Keeper/main.swift -o "$QA_DIR/keeper-tests"
"$QA_DIR/keeper-tests"
xcrun swiftc -parse-as-library TrollRoute/Storage/SharedPreferences.swift \
  Tests/Keeper/ownership.swift -o "$QA_DIR/ownership-tests"
# The shared storage regression requires both root creation and a real UID drop.
sudo -n "$QA_DIR/ownership-tests" "$QA_DIR/ownership"
