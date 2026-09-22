#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/location-access-qa
xcrun swiftc TrollRoute/LocationAccess.swift Tests/LocationAccess/main.swift -o build/location-access-qa/check
build/location-access-qa/check
