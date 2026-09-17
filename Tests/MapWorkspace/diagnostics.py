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
        "longPress = press\n        }": '''longPress = press
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--hold-only") {
                mapView.removeGestureRecognizer(tap); mapView.removeGestureRecognizer(doubleTap)
                singleTap = nil; doubleTapGuard = nil
            }
            if args.contains("--taps-only") {
                press.isEnabled = false; mapView.removeGestureRecognizer(press); longPress = nil
            }
        }''',
        "// MapKit has its own hold recognizer.": '''workspaceTrace("simultaneous \\(type(of: gestureRecognizer)) state=\\(gestureRecognizer.state.rawValue) / \\(type(of: other)) state=\\(other.state.rawValue)")
            if ProcessInfo.processInfo.arguments.contains("--coexist-hold"),
               gestureRecognizer === longPress || other === longPress { return true }
            // MapKit has its own hold recognizer.''',
        "gestureRecognizer === doubleTapGuard || other === doubleTapGuard": "return gestureRecognizer === doubleTapGuard || other === doubleTapGuard",
        "context.coordinator.longPress?.isEnabled = onLongPress != nil": '''workspaceTrace("update hold before=\\(String(describing: context.coordinator.longPress?.state.rawValue)), enabled=\\(onLongPress != nil)")
        context.coordinator.longPress?.isEnabled = onLongPress != nil
        workspaceTrace("update hold after=\\(String(describing: context.coordinator.longPress?.state.rawValue))")''',
        "let tap = UITapGestureRecognizer(target:": "let tap = TracedTapRecognizer(target:",
        "let doubleTap = UITapGestureRecognizer(target:": "let doubleTap = TracedTapRecognizer(target:",
        "context.coordinator.installTapRecognizers(on: mapView)": 'if !ProcessInfo.processInfo.arguments.contains("gestures-native") { context.coordinator.installTapRecognizers(on: mapView) }',

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

with (output / "CustomMapView.swift").open("a", encoding="utf-8") as f:
    f.write(r'''
// Test-only touch observation. All recognition is still performed by UIKit.
final class TracedTapRecognizer: UITapGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { workspaceTrace("raw began required=\(numberOfTapsRequired), count=\(touch.tapCount), time=\(touch.timestamp), state=\(state.rawValue)") }
        super.touchesBegan(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { workspaceTrace("raw ended required=\(numberOfTapsRequired), count=\(touch.tapCount), time=\(touch.timestamp), state=\(state.rawValue)") }
        super.touchesEnded(touches, with: event)
    }
}
''')
