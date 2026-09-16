"""Add observation-only traces to the production sources used by the UI host."""
from pathlib import Path
import sys

output = Path(sys.argv[1])
sources = {
    "LongPressRoute.swift": {
        "pending = request": 'workspaceTrace("pending \\(request.id)")\n        pending = request',
        "func confirmRequest(_ request: LongPressRouteRequest) {": 'func confirmRequest(_ request: LongPressRouteRequest) {\n        workspaceTrace("confirm \\(request.id), pending=\\(String(describing: pending?.id)), locating=\\(isLocating)")',
        "create(LongPressRouteEndpoints": 'workspaceTrace("create \\(request.id)")\n        create(LongPressRouteEndpoints',
        "pending = nil": 'workspaceTrace("cancel pending=\\(String(describing: pending?.id))")\n        pending = nil',
    },
    "CustomMapView.swift": {
        "var view = touch.view": 'workspaceTrace("touch recognizer=\\(type(of: gestureRecognizer)), count=\\(touch.tapCount), time=\\(touch.timestamp), state=\\(gestureRecognizer.state.rawValue)")\n            var view = touch.view',
        "handleMapTap(at: gesture.location(in: mapView), on: mapView)": 'workspaceTrace("single tap accepted time=\\(ProcessInfo.processInfo.systemUptime)")\n            handleMapTap(at: gesture.location(in: mapView), on: mapView)',
        "mapView.setRegion(region, animated: true)": 'workspaceTrace("setRegion \\(region)")\n            mapView.setRegion(region, animated: true)',
        "@objc private func ignoreDoubleTap(_ gesture: UITapGestureRecognizer) {}": '@objc private func ignoreDoubleTap(_ gesture: UITapGestureRecognizer) { workspaceTrace("double tap guard recognized") }',
        "positionBadges(on: mapView) }": 'workspaceTrace("region changed \\(mapView.region)"); WorkspaceMapObservation.shared.changed(mapView.region); positionBadges(on: mapView) }',
    },
}
for name, replacements in sources.items():
    source = (Path("TrollRoute/LocSim") / name).read_text(encoding="utf-8")
    for old, new in replacements.items():
        assert source.count(old) == 1, (name, old)
        source = source.replace(old, new)
    (output / name).write_text(source, encoding="utf-8")
