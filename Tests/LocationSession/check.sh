#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
QA_DIR="$PWD/build/location-session-qa"
mkdir -p "$QA_DIR"
python3 - "$QA_DIR/RouteLocationSample.swift" <<'PY'
from pathlib import Path
import sys
source = Path('TrollRoute/LocSim/LocSimManager.swift').read_text()
Path(sys.argv[1]).write_text(source.split('class LocSimManager {')[0])
PY
xcrun swiftc -parse-as-library TrollRoute/Storage/SharedPreferences.swift \
  TrollRoute/LocSim/RouteElevation.swift TrollRoute/LocSim/Altitude.swift TrollRoute/LocSim/LocationSession.swift \
  "$QA_DIR/RouteLocationSample.swift" Tests/LocationSession/main.swift -o "$QA_DIR/session-tests"
"$QA_DIR/session-tests"
xcrun swiftc -parse-as-library TrollRoute/Storage/SharedPreferences.swift \
  TrollRoute/LocSim/RouteElevation.swift TrollRoute/LocSim/Altitude.swift TrollRoute/LocSim/LocationSession.swift \
  Tests/LocationSession/Lease.swift -o "$QA_DIR/lease-tests"
"$QA_DIR/lease-tests"
