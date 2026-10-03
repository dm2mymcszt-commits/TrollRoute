import Foundation
import CoreLocation

@MainActor final class PendingElevation {
    var requests: [(CLLocationCoordinate2D, CheckedContinuation<Double?, Never>)] = []
    func lookup(_ coordinate: CLLocationCoordinate2D) async -> Double? {
        await withCheckedContinuation { requests.append((coordinate, $0)) }
    }
    func answer(_ value: Double?) { requests.removeFirst().1.resume(returning: value) }
}

@main struct AltitudeTests {
    @MainActor static func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Timed out waiting for elevation state")
    }
    @MainActor static func main() async {
        for (text, value) in [("12,5", 12.5), ("12.5", 12.5), ("-250", -250), ("-.5", -0.5), (" +42 ", 42)] {
            precondition(AltitudeProfile.parse(text) == value)
        }
        for text in ["", "-", "NaN", "inf", "12,5.6", "1,234,5", "abc", "1e999"] {
            precondition(AltitudeProfile.parse(text) == nil)
        }
        precondition(ElevationLookup.decode(Data(#"{"elevation":[-420.5]}"#.utf8)) == -420.5)
        for text in [#"{"elevation":[null]}"#, #"{"error":true}"#, #"{"elevation":[]}"#, #"{"elevation":[-9999]}"#] {
            precondition(ElevationLookup.decode(Data(text.utf8)) == nil)
        }
        let suite = "altitude-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AltitudeSettings(defaults: defaults)
        precondition(settings.profile.mode == .automatic)
        settings.setCustom(250)
        let restored = AltitudeSettings(defaults: defaults)
        precondition(restored.profile.mode == .custom && restored.profile.customMeters == 250)

        let pending = PendingElevation()
        var delivered: [CLLocation] = []
        var inputLocation: CLLocation?
        let controller = AltitudeController(settings: settings, defaults: defaults, interval: 0,
            lookup: { await pending.lookup($0) }, currentLocation: { inputLocation }, deliver: { delivered.append($0) })
        func receive(_ location: CLLocation) { inputLocation = location; controller.receive() }
        let start = CLLocationCoordinate2D(latitude: 44.817, longitude: -0.585)
        let next = CLLocationCoordinate2D(latitude: 44.827, longitude: -0.575)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        func sample(_ coordinate: CLLocationCoordinate2D, speed: Double = 13.9) -> CLLocation {
            RouteLocationSample.make(coordinate: coordinate, course: 271.5, speed: speed, timestamp: timestamp)
        }
        receive(sample(start))
        precondition(delivered.last!.altitude == 250 && delivered.last!.verticalAccuracy > 0)
        precondition(delivered.last!.speed == 13.9 && delivered.last!.speedAccuracy == 0)
        precondition(delivered.last!.course == 271.5 && delivered.last!.courseAccuracy == 0)
        precondition(delivered.last!.timestamp == timestamp && delivered.last!.horizontalAccuracy == 5)
        settings.setCustom(12.5)
        precondition(delivered.last!.altitude == 12.5) // Active location changes immediately.

        settings.reset()
        precondition(delivered.last!.verticalAccuracy < 0)
        precondition(AltitudeSettings(defaults: defaults).profile.mode == .automatic)
        await waitFor { pending.requests.count == 1 }
        receive(sample(next, speed: 120 / 3.6))
        pending.answer(18)
        await waitFor { pending.requests.count == 1 }
        precondition(delivered.last!.coordinate.latitude == next.latitude)
        precondition(delivered.last!.verticalAccuracy < 0) // Old-place height must not leak.
        precondition(delivered.last!.speed == 120 / 3.6)
        pending.answer(37)
        await waitFor { controller.currentMeters == 37 }
        precondition(delivered.last!.altitude == 37 && delivered.last!.verticalAccuracy > 0)
        precondition(delivered.last!.speed == 120 / 3.6 && delivered.last!.courseAccuracy == 0)
        receive(sample(next, speed: 0))
        precondition(delivered.last!.speed == 0 && delivered.last!.courseAccuracy < 0)
        receive(sample(start))
        precondition(delivered.last!.altitude == 18) // Repeated route uses cached terrain.

        let distant = CLLocationCoordinate2D(latitude: 45, longitude: 1)
        receive(sample(distant))
        await waitFor { pending.requests.count == 1 }
        settings.setCustom(-20)
        pending.answer(999)
        try? await Task.sleep(nanoseconds: 20_000_000)
        precondition(delivered.last!.altitude == -20) // Late result cannot override Custom.
        settings.reset()
        await waitFor { pending.requests.count == 1 }
        inputLocation = nil
        controller.stop()
        let count = delivered.count
        pending.answer(123)
        try? await Task.sleep(nanoseconds: 20_000_000)
        precondition(delivered.count == count && !controller.isActive && controller.currentMeters == nil)
        settings.setCustom(250)
        precondition(delivered.count == count) // Changing settings after Stop never restarts spoofing.
        inputLocation = sample(start, speed: 230)
        controller.receive(routeDistance: 1000, flightAltitude: 9000)
        precondition(controller.flightAltitude == 9000 && delivered.last!.altitude == 9000)
        precondition(delivered.last!.speed == 230 && delivered.last!.course == 271.5)
        precondition(delivered.last!.horizontalAccuracy == 5 && delivered.last!.speedAccuracy == 0)
        settings.setCustom(888)
        precondition(delivered.last!.altitude == 9000, "Custom changes are saved but cannot override a flight")
        settings.reset()
        precondition(delivered.last!.altitude == 9000, "Automatic cannot override a flight")
        inputLocation = sample(next, speed: 0)
        controller.receive(routeDistance: 2000, flightAltitude: 37)
        controller.finishFlight()
        precondition(controller.flightAltitude == nil && delivered.last!.altitude == 37)
        settings.setCustom(250)
        precondition(delivered.last!.altitude == 250, "Normal altitude applies after landing")
        controller.receive(routeDistance: 1000, flightAltitude: 8000)
        controller.holdCaptured(AltitudeController.applying(7000, to: sample(next, speed: 0), accuracy: 10))
        precondition(controller.flightAltitude == nil && delivered.last!.altitude == 7000)
        inputLocation = nil
        controller.stop()
        print("PASS: saved altitude, decimal parsing, unknown validity, current motion, cache, stale results, and Stop")
    }
}
