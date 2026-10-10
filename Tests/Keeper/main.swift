import Foundation
import CoreLocation

final class CLSimulationManager {
    static var operations: [String] = []
    static var samples: [CLLocation] = []
    func stopLocationSimulation() { Self.operations.append("stop") }
    func clearSimulatedLocations() { Self.operations.append("clear") }
    func appendSimulatedLocation(_ location: CLLocation) { Self.operations.append("append"); Self.samples.append(location) }
    func flush() { Self.operations.append("flush") }
    func startLocationSimulation() { Self.operations.append("start") }
}

@main struct KeeperTests {
    static func main() throws {
        var alive = false; var starts = 0; var stops = 0
        let keeper = KeeperLifecycle(running: { alive }, spawn: { alive = true; starts += 1 },
                                     terminate: { alive = false; stops += 1 })
        try keeper.ensureRunning(); try keeper.ensureRunning()
        precondition(starts == 1)
        try keeper.stop(); precondition(!alive && stops == 1)
        try keeper.ensureRunning(); precondition(starts == 2)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lease = LocationLeaseStore(url: dir.appendingPathComponent("authority.json"))
        let token = UUID(); _ = try lease.claim(token)
        let point = CLLocation(coordinate: .init(latitude: 40, longitude: 2), altitude: 88,
            horizontalAccuracy: 3, verticalAccuracy: 4, course: 145, courseAccuracy: 0.25,
            speed: 28, speedAccuracy: 0.125, timestamp: Date(timeIntervalSince1970: 1234))
        try lease.perform(token) { $0 = .init(kind: .route, current: SessionLocation(point)) }
        var process = "old"; var scheduled: [() -> Void] = []; var restores = 0
        let recovery = KeeperRecovery(identity: { process }, restore: {
            try lease.restoreCurrent { location in
                restores += 1
                CoreLocationSimulationDriver().inject(location, reason: .stateChange)
            }
        }, schedule: { _, work in scheduled.append(work) })
        process = ""; recovery.processExited(); precondition(restores == 0)
        process = "new"; scheduled.removeFirst()()
        precondition(restores == 1)
        precondition(CLSimulationManager.operations == ["stop", "clear", "append", "flush", "start"])
        precondition(SessionLocation(CLSimulationManager.samples.last!) == SessionLocation(point))
        _ = try lease.stop(token, driverStop: {})
        scheduled.forEach { $0() }; precondition(restores == 1)
        recovery.stop(); recovery.processExited(); precondition(restores == 1)
        // A callback already queued when Stop begins must recheck persisted authority.
        let owner = UUID(); _ = try lease.claim(owner)
        try lease.perform(owner) { $0 = .init(kind: .stationary, current: SessionLocation(point)) }
        enum StopFailure: Error { case failed }
        do { _ = try lease.stop(owner) { throw StopFailure.failed }; preconditionFailure() }
        catch StopFailure.failed {}
        let afterFailedEffect = try lease.read()
        precondition(afterFailedEffect.owner == nil && !afterFailedEffect.snapshot.isActive)
        let restoredAfterStop = try lease.restoreCurrent { _ in preconditionFailure("Restore won after Stop") }
        precondition(!restoredAfterStop)
        try keeper.stop(); try keeper.stop() // no keeper is a successful no-op for the controller
        print("PASS: revocation persists even when the external Stop fails; queued restore cannot resurrect it")
        print("PASS: exit/replacement full sequence, exact motion metadata, inactive authority and cancellation")
        let log = KeeperLog(directory: dir)
        for index in 0..<700 { try log.append(.restoreSent, newPID: 42, attempt: index) }
        let journal = try log.read()
        precondition(journal.events.count == 512)
        let bytes = try Data(contentsOf: log.file.url)
        precondition(bytes.count <= KeeperLog.maximumBytes)
        let text = try log.text()
        precondition(text.contains("restoreSent") && text.contains(". ") == false)
        let raw = String(data: bytes, encoding: .utf8)!
        for forbidden in ["latitude", "longitude", "coordinate", "address", "course", "speed"] { precondition(!raw.contains(forbidden)) }
        precondition(journal.events.last!.line.range(of: #"\.\d{3}Z"#, options: .regularExpression) != nil)
        print("PASS: bounded log, millisecond timestamps, only typed non-location fields")
        let report = KeeperDiagnosticReport.render(start: 0, end: 10, samples: [
            .init(received: Date(), uptime: 2, timestamp: Date(), simulated: false, matches: false),
            .init(received: Date(), uptime: 2.375, timestamp: Date(), simulated: true, matches: true)],
            events: [], markerVerified: true, interrupted: false)
        precondition(report.contains("0.375 seconds") && report.contains("not a bound"))
        let unknown = KeeperDiagnosticReport.render(start: 0, end: 10, samples: [], events: [], markerVerified: false, interrupted: true)
        precondition(unknown.contains("INCOMPLETE") && unknown.contains("cannot reliably"))
        print("PASS: diagnostic measures received intervals and labels unknown/interrupted observations")
        print("PASS: fake spawner starts once, stops, and starts a new keeper")
    }
}
