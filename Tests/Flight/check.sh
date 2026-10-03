#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/flight-qa
xcrun swiftc TrollRoute/LocSim/Flight.swift Tests/Flight/main.swift -o build/flight-qa/flight-tests
build/flight-qa/flight-tests
xcrun swiftc -parse-as-library TrollRoute/LocSim/Flight.swift Tests/Flight/ElevationTests.swift -o build/flight-qa/elevation-tests
build/flight-qa/elevation-tests
