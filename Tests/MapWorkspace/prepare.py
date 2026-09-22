"""Expose map-region changes to XCTest without changing gesture recognition."""
from pathlib import Path
import sys

output = Path(sys.argv[1])
source = Path("TrollRoute/LocSim/CustomMapView.swift").read_text(encoding="utf-8")
hook = "positionBadges(on: mapView) }"
assert source.count(hook) == 1
source = source.replace(hook, "WorkspaceMapObservation.shared.changed(mapView.region); " + hook)
(output / "CustomMapView.swift").write_text(source, encoding="utf-8")
(output / "LongPressRoute.swift").write_bytes(Path("TrollRoute/LocSim/LongPressRoute.swift").read_bytes())
