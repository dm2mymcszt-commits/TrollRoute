import Foundation
import CoreLocation

final class LeaseDriver: LocationSimulationDriver {
    var samples: [CLLocation] = []
    var stops = 0
    var relinquishes = 0
    func inject(_ location: CLLocation, reason: LocationInjectionReason) { samples.append(location) }
    func stop() { stops += 1 }
    func relinquish() { relinquishes += 1 }
}

@MainActor final class DeferredHeight {
    var completion: CheckedContinuation<Double?, Never>?
    func lookup(_ point: CLLocationCoordinate2D) async -> Double? {
        await withCheckedContinuation { completion = $0 }
    }
}

@main struct LeasedOwnerTests {
    @MainActor static func main() async throws {
        let suite = "leased-owner-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let lease = LocationLeaseStore(url: directory.appendingPathComponent("session.json"))
        let settings = AltitudeSettings(defaults: defaults)
        settings.setCustom(250)
        let driver = LeaseDriver()
        let owner = LocationSession(driver: driver, defaults: defaults, settings: settings,
                                    injectionInterval: 60, lease: lease, lookup: { _ in nil })
        func point(_ lat: Double, speed: Double = 0) -> CLLocation {
            CLLocation(coordinate: .init(latitude: lat, longitude: -0.6), altitude: 20,
                horizontalAccuracy: 5, verticalAccuracy: 1, course: 90, courseAccuracy: 0,
                speed: speed, speedAccuracy: 0, timestamp: Date())
        }
        owner.receive(point(44), kind: .stationary)
        precondition(driver.samples.isEmpty, "Callbacks must not acquire authority")
        owner.receive(point(44), kind: .stationary, newIntent: true)
        precondition(owner.current?.meters == 250 && driver.samples.count == 1)
        let previous = owner.current
        precondition(owner.beginRoute())
        owner.receive(point(44.1, speed: 50 / 3.6), kind: .route)
        precondition(owner.snapshot.beforeRoute == previous)
        owner.receive(point(44.2, speed: 120 / 3.6), kind: .route)
        let count = driver.samples.count // Continuous sample is waiting in the queue.
        let external = SessionLocation(point(45))
        try lease.move(UUID(), sample: external) { _ in }
        owner.finishHolding() // Would flush the pending sample without revocation.
        owner.receive(point(44.3, speed: 50 / 3.6), kind: .route)
        owner.stop(newIntent: false)
        precondition(driver.samples.count == count && driver.stops == 0)
        precondition(owner.current == external && driver.relinquishes == 1)
        settings.setCustom(12.5) // An explicit user edit adopts the new held spot.
        precondition(owner.current?.latitude == 45 && owner.current?.meters == 12.5)
        precondition(driver.samples.last?.speed == 0)
        owner.stop()
        precondition(driver.stops == 1 && !owner.isActive)
        settings.reset()
        precondition(!owner.isActive, "Changing altitude after Stop must not restart")

        let pending = DeferredHeight()
        defaults.removeObject(forKey: "elevationNextLookup")
        let lateDriver = LeaseDriver()
        let late = LocationSession(driver: lateDriver, defaults: defaults, settings: settings,
            injectionInterval: 0, lease: lease, lookup: { await pending.lookup($0) })
        late.receive(point(46), kind: .stationary, newIntent: true)
        for _ in 0..<200 {
            if pending.completion != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(pending.completion != nil)
        let beforeAnswer = lateDriver.samples.count
        try lease.move(UUID(), sample: external) { _ in }
        late.refreshShared()
        pending.completion?.resume(returning: 999)
        pending.completion = nil
        // Let the canceled async continuation return through the real controller.
        for _ in 0..<10 { await Task.yield() }
        precondition(lateDriver.samples.count == beforeAnswer && late.current == external)
        let reloadDriver = LeaseDriver()
        let reopened = LocationSession(driver: reloadDriver, defaults: defaults, settings: settings, lease: lease)
        precondition(reopened.current == external && reloadDriver.samples.isEmpty)
        reopened.receive(point(47), kind: .route)
        precondition(reloadDriver.samples.isEmpty, "Relaunch never resumes a stale route")
        let unavailableDriver = LeaseDriver()
        let unavailable = LocationSession(driver: unavailableDriver, defaults: defaults,
            settings: settings, requiresLease: true)
        unavailable.receive(point(44), kind: .stationary, newIntent: true)
        precondition(unavailable.error != nil && unavailableDriver.samples.isEmpty)
        print("PASS: actual owner lease checks, queued/late callback revocation, altitude edit adoption, explicit Stop, relaunch and unavailable storage")
    }
}
