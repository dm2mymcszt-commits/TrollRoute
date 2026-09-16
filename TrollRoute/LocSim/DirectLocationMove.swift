import Foundation
import CoreLocation

/// Extension-side action. No application launch, inbox polling or UI receipt is
/// treated as a location delivery. The real driver runs inside the authority lock.
@MainActor struct DirectLocationMove {
    let lease: LocationLeaseStore?
    let profile: () -> AltitudeProfile
    let lookup: (CLLocationCoordinate2D) async -> Double?
    let inject: (CLLocation) throws -> Void
    let changed: () -> Void

    func perform(id: UUID, coordinate: CLLocationCoordinate2D) async throws {
        guard CLLocationCoordinate2DIsValid(coordinate), let lease = lease else {
            throw MoveError.unavailable
        }
        let initial = try lease.read()
        let sample: SessionLocation
        if let receipt = initial.moves[id] {
            guard receipt.sample.latitude == coordinate.latitude,
                  receipt.sample.longitude == coordinate.longitude else { throw MoveError.conflict }
            sample = receipt.sample // Retry the identical sample, including timestamp and altitude.
        } else {
            let setting = profile()
            let meters = setting.mode == .custom ? setting.customMeters : await lookup(coordinate)
            try Task.checkCancellation()
            sample = SessionLocation(AltitudeController.applying(meters,
                to: CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5,
                    verticalAccuracy: -1, course: 0, courseAccuracy: -1,
                    speed: 0, speedAccuracy: 0, timestamp: Date()),
                accuracy: setting.mode == .custom ? 1 : 90))
        }
        try Task.checkCancellation()
        // Wake even after a failed driver/write: a pending checkpoint has already
        // revoked the old route. It must not resume while this action is retried.
        defer { changed() }
        do {
            try lease.move(id, sample: sample, expectedOwner: .matching(initial.owner)) { location in
                changed() // Revocation is durable before the driver's external effect.
                try inject(location)
            }
        } catch LocationLeaseStore.Failure.supersededMove { throw MoveError.superseded }
    }

    enum MoveError: LocalizedError {
        case unavailable, conflict, superseded
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Couldn't access shared location state. Try sharing again."
            case .conflict: return "The shared location changed. Share it again."
            case .superseded: return "A newer location action replaced this move. Share again to move here."
            }
        }
    }
}
