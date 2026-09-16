import Foundation
import CoreLocation

@main struct DirectMoveTests {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("direct-move-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let lease = LocationLeaseStore(url: directory.appendingPathComponent("authority.json"))
        let coordinate = CLLocationCoordinate2D(latitude: 44.817059, longitude: -0.585746)
        let old = UUID()
        _ = try lease.claim(old)
        var output: [SessionLocation] = []
        var events: [String] = []
        var lookups = 0
        var setting = AltitudeProfile(mode: .custom, customMeters: 250)
        var fail = false
        enum Expected: Error { case driver }
        let mover = DirectLocationMove(lease: lease, profile: { setting }, lookup: { _ in
            lookups += 1; return 31
        }, inject: { location in
            events.append("inject")
            if fail { throw Expected.driver }
            output.append(SessionLocation(location))
        }, changed: { events.append("wake") })
        let first = UUID()
        try await mover.perform(id: first, coordinate: coordinate)
        precondition(output.count == 1 && lookups == 0 && events == ["wake", "inject", "wake"])
        let sample = output[0]
        precondition(sample.meters == 250 && sample.speed == 0 && sample.courseAccuracy == -1)
        precondition(sample.horizontalAccuracy == 5 && sample.speedAccuracy == 0)
        let state = try lease.read()
        precondition(state.snapshot.current == sample && state.snapshot.kind == .stationary)
        precondition(state.moves[first]?.status == .applied)
        let staleAccepted = try lease.perform(old) { _ in fatalError("Stale writer ran") }
        precondition(!staleAccepted)
        // A reopened service retries the original command without replay or lookup.
        setting = AltitudeProfile(mode: .custom, customMeters: -12.5)
        try await mover.perform(id: first, coordinate: coordinate)
        precondition(output.count == 1 && lookups == 0)
        try await mover.perform(id: UUID(), coordinate: coordinate)
        precondition(output.last?.meters == -12.5)
        setting = AltitudeProfile()
        fail = true
        let retry = UUID()
        do { try await mover.perform(id: retry, coordinate: coordinate); fatalError("Expected driver failure") }
        catch Expected.driver { }
        let pending = try lease.read().moves[retry]!
        precondition(pending.status == .pending && lookups == 1)
        fail = false
        try await mover.perform(id: retry, coordinate: coordinate)
        precondition(output.last == pending.sample && lookups == 1)
        precondition(output.last?.meters == 31)

        let unavailable = DirectLocationMove(lease: lease, profile: { AltitudeProfile() },
            lookup: { _ in nil }, inject: { output.append(SessionLocation($0)) }, changed: {})
        try await unavailable.perform(id: UUID(), coordinate: coordinate)
        precondition(output.last?.meters == nil && output.last?.verticalAccuracy == -1)

        let latest = UUID()
        let competing = DirectLocationMove(lease: lease, profile: { AltitudeProfile() }, lookup: { _ in
            _ = try! lease.claim(latest) // New user action while elevation was awaited.
            return 20
        }, inject: { _ in fatalError("An older async request overwrote a new user action") }, changed: {})
        do { try await competing.perform(id: UUID(), coordinate: coordinate); fatalError("Expected supersession") }
        catch DirectLocationMove.MoveError.superseded { }
        let afterCompetition = try lease.read()
        precondition(afterCompetition.owner == latest)
        let missing = DirectLocationMove(lease: nil, profile: { setting }, lookup: { _ in nil },
            inject: { _ in fatalError("Missing storage must prevent delivery") }, changed: {})
        do { try await missing.perform(id: UUID(), coordinate: coordinate); fatalError("Expected storage error") }
        catch DirectLocationMove.MoveError.unavailable { }
        let canceled = Task { @MainActor in
            try await unavailable.perform(id: UUID(), coordinate: coordinate)
        }
        canceled.cancel()
        do { try await canceled.value; fatalError("Expected cancellation") }
        catch is CancellationError { }
        print("PASS: direct Go driver ordering, saved custom/automatic/unknown altitude, stationary metadata, receipts/retry, revocation, competing user intent, missing storage and cancellation")
    }
}
