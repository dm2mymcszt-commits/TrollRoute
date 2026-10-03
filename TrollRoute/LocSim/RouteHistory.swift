import Foundation
import CoreLocation
import Combine

struct HistoryCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    init(_ coordinate: CLLocationCoordinate2D) { latitude = coordinate.latitude; longitude = coordinate.longitude }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct RouteHistoryEntry: Codable, Identifiable {
    var id = UUID()
    let start: RouteFinishDestination
    let destination: RouteFinishDestination
    let mode: String
    let symbol: String
    let speedKmh: Double
    let routeName: String
    let coordinates: [HistoryCoordinate]
    let distance: Double
    let expectedTravelTime: Double
    let trafficLabel: String
    let finish: RouteFinishConfiguration
    let date: Date
    let departureAirport: FlightAirport?
    let arrivalAirport: FlightAirport?

    var isValid: Bool {
        CLLocationCoordinate2DIsValid(start.coordinate) && CLLocationCoordinate2DIsValid(destination.coordinate) &&
        coordinates.count >= 2 && coordinates.allSatisfy { CLLocationCoordinate2DIsValid($0.coordinate) } &&
        speedKmh.isFinite && speedKmh > 0 && distance.isFinite && distance > 0 &&
        expectedTravelTime.isFinite && expectedTravelTime >= 0 && date.timeIntervalSince1970.isFinite && finish.isValid
    }
    func sameTrip(as other: RouteHistoryEntry) -> Bool {
        mode == other.mode && HistoryCoordinate(start.coordinate) == HistoryCoordinate(other.start.coordinate) &&
        HistoryCoordinate(destination.coordinate) == HistoryCoordinate(other.destination.coordinate) &&
        coordinates == other.coordinates && departureAirport?.id == other.departureAirport?.id &&
        arrivalAirport?.id == other.arrivalAirport?.id
    }
}

/// Local Application Support, explicitly excluded from device/cloud backups.
/// The app never uploads this file or starts a route when it is loaded.
final class RouteHistoryStore: ObservableObject {
    static let shared = RouteHistoryStore()
    @Published private(set) var entries: [RouteHistoryEntry] = []
    @Published private(set) var error: String?
    private let url: URL
    private var unreadable = false
    private struct Archive: Codable { let version: Int; let entries: [RouteHistoryEntry] }
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RouteHistory", isDirectory: true).appendingPathComponent("history.v1.plist")
    }
    init(url: URL = RouteHistoryStore.defaultURL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let archive = try PropertyListDecoder().decode(Archive.self, from: Data(contentsOf: url))
            guard archive.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            entries = Array(archive.entries.filter(\.isValid).sorted { $0.date > $1.date }.prefix(50))
        } catch { unreadable = true; self.error = "Couldn't read route history. Your saved file has been kept." }
    }
    @discardableResult
    func record(_ entry: RouteHistoryEntry) -> Bool {
        guard entry.isValid else { return false }
        let existing = entries.first { $0.sameTrip(as: entry) }
        var newest = entry
        if let existing = existing { newest.id = existing.id }
        let values = ([newest] + entries.filter { !$0.sameTrip(as: entry) }).sorted { $0.date > $1.date }
        return save(Array(values.prefix(50)))
    }
    @discardableResult
    func delete(_ id: UUID) -> Bool { save(entries.filter { $0.id != id }) }
    @discardableResult
    func clear() -> Bool { save([]) }
    private func save(_ values: [RouteHistoryEntry]) -> Bool {
        // Do not overwrite an unreadable existing archive on the next route.
        // Explicit Clear is the recovery action offered by the History screen.
        if unreadable && !values.isEmpty { return false }
        do {
            var directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var policy = URLResourceValues(); policy.isExcludedFromBackup = true
            try directory.setResourceValues(policy)
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let data = try encoder.encode(Archive(version: 1, entries: values))
            try data.write(to: url, options: .atomic)
            entries = values; error = nil; unreadable = false
            return true
        } catch {
            self.error = "Couldn't save route history on this device."
            return false
        }
    }
}
