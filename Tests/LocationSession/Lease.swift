import Foundation
import CoreLocation

@main struct LeaseTests {
    static func require(_ condition: Bool, _ message: String = "Lease invariant failed") { precondition(condition, message) }
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    static func sample(_ latitude: Double, speed: Double = 0) -> SessionLocation {
        SessionLocation(CLLocation(coordinate: .init(latitude: latitude, longitude: -0.58),
            altitude: 250, horizontalAccuracy: 5, verticalAccuracy: 0,
            course: 90, courseAccuracy: 0, speed: speed, speedAccuracy: 0, timestamp: fixedDate))
    }
    static func signal(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
    static func gate() { require(FileHandle.standardInput.readData(ofLength: 1).count == 1) }
    static func log(_ text: String, at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((text + "\n").utf8))
    }
    static func main() throws {
        let args = CommandLine.arguments
        if args.count > 1 {
            let lease = LocationLeaseStore(url: URL(fileURLWithPath: args[2]))
            let token = UUID(uuidString: args[3])!
            let trace = URL(fileURLWithPath: args[4])
            switch args[1] {
            case "--stale":
                signal("R"); gate()
                let delivered = try lease.perform(token) { state in
                    try log("stale", at: trace); state.current = sample(44.1, speed: 10)
                }
                let stopped = try lease.stop(token) { try log("stale-stop", at: trace) }
                require(!delivered && !stopped)
            case "--writer":
                let delivered = try lease.perform(token) { state in
                    signal("R"); gate() // Hold the real cross-process lock.
                    try log("old", at: trace); state.current = sample(44.2, speed: 10)
                }
                require(delivered)
            case "--move":
                signal("R")
                let delivered = try lease.move(token, sample: sample(44.3)) { _ in try log("new", at: trace) }
                require(delivered)
            default: fatalError("Unknown command")
            }
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lease-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let trace = directory.appendingPathComponent("driver.log")
        try Data().write(to: trace)
        let initial = LocationSessionSnapshot(kind: .stationary, current: sample(44))
        let lease = LocationLeaseStore(url: url, initial: { initial })
        require(try lease.read().snapshot == initial)
        let route = UUID()
        _ = try lease.claim(route)
        _ = try lease.perform(route) { state in
            state.beforeRoute = state.current; state.kind = .route; state.current = sample(44.1, speed: 50 / 3.6)
        }
        func child(_ mode: String, token: UUID) throws -> (Process, Pipe) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = [mode, url.path, token.uuidString, trace.path]
            let input = Pipe(), output = Pipe()
            process.standardInput = input; process.standardOutput = output
            try process.run()
            require(output.fileHandleForReading.readData(ofLength: 1) == Data("R".utf8))
            return (process, input)
        }
        func release(_ pair: (Process, Pipe)) {
            pair.1.fileHandleForWriting.write(Data("x".utf8))
            pair.0.waitUntilExit(); require(pair.0.terminationStatus == 0)
        }
        // A suspended process resumes AFTER another process has moved. Both
        // injection and stop from its old route token must be refused.
        let suspended = try child("--stale", token: route)
        let request = UUID()
        var injections = 0
        let moved = try lease.move(request, sample: sample(44.3)) { location in
            injections += 1
            require(location.speed == 0 && location.altitude == 250 && location.course == 90)
        }
        require(moved)
        release(suspended)
        require(try String(contentsOf: trace, encoding: .utf8).isEmpty)
        let reopened = LocationLeaseStore(url: url)
        require(try reopened.read().snapshot == LocationSessionSnapshot(kind: .stationary, current: sample(44.3)))
        let duplicate = try reopened.move(request, sample: sample(44.3)) { _ in injections += 1 }
        require(!duplicate && injections == 1, "A durable receipt must prevent replay")
        do {
            try reopened.move(request, sample: sample(44.4)) { _ in fatalError("Conflicting request injected") }
            fatalError("Conflicting UUID accepted")
        } catch LocationLeaseStore.Failure.conflictingMove {}

        // A writer already inside its driver call must finish before takeover;
        // the new move is last. Checking a token outside the lock would fail this.
        let owner = UUID(); _ = try lease.claim(owner)
        let writer = try child("--writer", token: owner)
        let takeover = try child("--move", token: UUID())
        release(writer)
        takeover.0.waitUntilExit(); require(takeover.0.terminationStatus == 0)
        require(try String(contentsOf: trace, encoding: .utf8) == "old\nnew\n")
        require(try lease.read().snapshot.current == sample(44.3))

        enum Expected: Error { case unavailable }
        let beforeFailure = UUID(); _ = try lease.claim(beforeFailure)
        let failedRequest = UUID()
        do {
            try lease.move(failedRequest, sample: sample(44.5)) { _ in throw Expected.unavailable }
            fatalError("Driver failure reported success")
        } catch Expected.unavailable {}
        require(try lease.read().moves[failedRequest]?.status == .pending)
        let staleAfterFailure = try lease.perform(beforeFailure) { _ in fatalError("Revoked writer ran after failure") }
        require(!staleAfterFailure)
        let recovered = try lease.move(failedRequest, sample: sample(44.5)) { _ in injections += 1 }
        require(recovered && injections == 2)

        let abandoned = UUID()
        do { try lease.move(abandoned, sample: sample(44.6)) { _ in throw Expected.unavailable } }
        catch Expected.unavailable {}
        let newIntent = UUID(); _ = try lease.claim(newIntent)
        do {
            try lease.move(abandoned, sample: sample(44.6)) { _ in fatalError("Old retry overwrote newer user action") }
            fatalError("Superseded move accepted")
        } catch LocationLeaseStore.Failure.supersededMove {}
        var stops = 0
        require(try lease.stop(newIntent) { stops += 1 })
        require(try !lease.stop(newIntent) { stops += 1 })
        let stoppedState = try lease.read()
        require(stops == 1 && stoppedState.snapshot.current == nil)
        require(try !lease.perform(newIntent) { _ in fatalError("Callback restarted stopped owner") })
        try Data("broken".utf8).write(to: url)
        do { _ = try lease.claim(UUID()); fatalError("Corrupt state silently reset") } catch is DecodingError {}
        print("PASS: cross-process lease, suspended writer/stop refusal, atomic driver ordering, durable Go receipts, failures/retries, supersession and metadata")
    }
}
