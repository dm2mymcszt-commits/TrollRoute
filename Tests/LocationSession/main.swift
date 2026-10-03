import Foundation
import CoreLocation

final class RecordingDriver: LocationSimulationDriver {
    var delivered: [CLLocation] = []
    var stops = 0
    func inject(_ location: CLLocation, reason: LocationInjectionReason) { delivered.append(location) }
    func stop() { stops += 1 }
}

@main struct SessionTests {
    @MainActor static func main() {
        let suite = "session-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AltitudeSettings(defaults: defaults)
        settings.setCustom(250)
        let driver = RecordingDriver()
        let session = LocationSession(driver: driver, defaults: defaults, settings: settings,
            injectionInterval: 0, lookup: { _ in nil })
        let store = LocationSessionStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func sample(_ lat: Double, _ lon: Double, speed: Double = 0) -> CLLocation {
            RouteLocationSample.make(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                course: 90, speed: speed, timestamp: date)
        }
        precondition(!session.isActive && session.snapshot.beforeRoute == nil)
        // Static positions represent every picker, map, favorite and shared-place move.
        session.receive(sample(31.23, 121.47), kind: .stationary)
        precondition(driver.delivered.count == 1, "Owner initialization must not inject twice")
        precondition(session.current!.coordinate.longitude == 121.47, "Storage is WGS-84, never map-transformed")
        precondition(session.current!.meters == 250 && session.snapshot.kind == .stationary)
        let previous = session.current!
        session.beginRoute()
        session.receive(sample(44.817, -0.585, speed: 50 / 3.6), kind: .route)
        precondition(session.snapshot.beforeRoute == previous)
        precondition(store.load() == session.snapshot)
        settings.setCustom(12.5)
        precondition(session.current!.meters == 12.5)
        precondition(session.snapshot.beforeRoute!.meters == 250, "Route snapshot must preserve the old altitude")
        precondition(session.current!.speed == 50 / 3.6 && session.current!.courseAccuracy == 0)
        session.receive(sample(44.82, -0.58, speed: 120 / 3.6), kind: .route)
        precondition(session.snapshot.beforeRoute == previous)
        precondition(session.current!.timestamp == date && session.current!.horizontalAccuracy == 5)
        session.receive(sample(44.83, -0.57), kind: .route)
        let count = driver.delivered.count
        session.finishHolding()
        precondition(driver.delivered.count == count, "Changing ownership must not add an injection")
        precondition(session.snapshot.kind == .stationary && session.current!.speed == 0)
        let held = session.current!
        session.beginRoute()
        precondition(session.snapshot.beforeRoute == held, "A previous route's held destination counts as a spoof")
        session.stop()
        precondition(!session.isActive && session.current == nil && session.snapshot.beforeRoute == nil)
        precondition(driver.stops == 1 && !store.load().isActive)
        settings.setCustom(-20)
        precondition(driver.delivered.count == count, "Settings after Stop must not restart injection")

        session.receive(sample(44.84, -0.56, speed: -1), kind: .joystick)
        precondition(session.snapshot.kind == .joystick && session.current!.speedAccuracy == -1)
        session.beginRoute()
        precondition(session.snapshot.beforeRoute!.meters == -20)
        session.stop()
        session.beginRoute()
        precondition(session.snapshot.beforeRoute == nil, "Starting from real location has no previous spoof")
        session.receive(sample(44.85, -0.55), kind: .route)
        session.finishHolding()
        // Simulate a second process reading the group, without moving anything.
        let reader = LocationSessionStore(defaults: UserDefaults(suiteName: suite)!)
        precondition(reader.load() == session.snapshot)
        let newDriver = RecordingDriver()
        let reopened = LocationSession(driver: newDriver, defaults: defaults, settings: settings)
        precondition(reopened.snapshot == session.snapshot && newDriver.delivered.isEmpty)
        let frozen = reopened.snapshot
        reopened.receive(sample(91, 0), kind: .stationary)
        precondition(reopened.snapshot == frozen && newDriver.delivered.isEmpty)
        defaults.set(Data("broken".utf8), forKey: "locationSession.v1")
        precondition(!reader.load().isActive)

        // Unknown altitude and every motion field round-trip through the group.
        let unknown = SessionLocation(sample(44, 1, speed: 500 / 3.6))
        let restored = try! JSONDecoder().decode(SessionLocation.self, from: JSONEncoder().encode(unknown))
        precondition(restored == unknown && restored.meters == nil)
        precondition(restored.location.verticalAccuracy == -1 && restored.location.speedAccuracy == 0)
        session.beginRoute()
        session.receive(sample(45, 2, speed: 230), kind: .route, routeDistance: 1000, flightAltitude: 10_500)
        precondition(session.current?.altitude == 10_500 && session.current?.speed == 230)
        settings.setCustom(123)
        precondition(session.current?.altitude == 10_500)
        session.receive(sample(46, 3, speed: 0), kind: .route, routeDistance: 2000, flightAltitude: 80)
        precondition(session.current?.altitude == 80 && session.current?.speed == 0)
        session.finishHolding()
        precondition(session.current?.altitude == 123 && session.current?.speed == 0)
        precondition(session.snapshot.kind == .stationary && session.altitudeController.flightAltitude == nil)
        session.stop()
        print("PASS: location ownership, previous spoof/altitude, real start, joystick, held destination, group round-trip, no replay, stop and unchanged motion")
    }
}
