#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/flight-qa
xcrun swiftc TrollRoute/LocSim/Flight.swift Tests/Flight/main.swift -o build/flight-qa/flight-tests
build/flight-qa/flight-tests
