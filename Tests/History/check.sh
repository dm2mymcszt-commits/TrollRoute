#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/history-qa
xcrun swiftc -parse-as-library TrollRoute/Storage/SharedPreferences.swift TrollRoute/LocSim/RouteFinish.swift \
  TrollRoute/LocSim/Flight.swift TrollRoute/LocSim/RouteHistory.swift Tests/History/main.swift -o build/history-qa/history-tests
build/history-qa/history-tests
