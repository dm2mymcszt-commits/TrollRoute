#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/activity-control-geometry
swiftc Tests/LiveActivity/ControlGeometry.swift Tests/LiveActivity/GeometryTests.swift \
  -o build/activity-control-geometry/check
build/activity-control-geometry/check
