import Foundation
import CoreLocation

@main struct HistoryTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("history-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.plist")
        let store = RouteHistoryStore(url: url)
        precondition(store.entries.isEmpty)
        func entry(_ i: Int, mode: String = "Driving", speed: Double = 50) -> RouteHistoryEntry {
            let a = CLLocationCoordinate2D(latitude: 40, longitude: Double(i) / 100)
            let b = CLLocationCoordinate2D(latitude: 41, longitude: Double(i) / 100)
            return RouteHistoryEntry(start: .init(name: "Start \(i)", address: "", coordinate: a),
                destination: .init(name: "End \(i)", address: "", coordinate: b), mode: mode, symbol: "map",
                speedKmh: speed, routeName: "Chosen route", coordinates: [HistoryCoordinate(a), HistoryCoordinate(b)],
                distance: 111_000, expectedTravelTime: 1000, trafficLabel: "Typical travel",
                finish: .init(action: .returnOnce), date: Date(timeIntervalSince1970: Double(i)),
                departureAirport: nil, arrivalAirport: nil)
        }
        for mode in ["Walking", "Cycling", "Driving", "Plane"] { precondition(store.record(entry(1, mode: mode))) }
        precondition(store.entries.count == 4, "Different modes remain separate trips")
        precondition(store.clear())
        for i in 1...55 { precondition(store.record(entry(i))) }
        precondition(store.entries.count == 50)
        precondition(store.entries.first!.start.name == "Start 55" && store.entries.last!.start.name == "Start 6")
        let saved = store.entries[10]
        let replay = RouteHistoryEntry(start: saved.start, destination: saved.destination, mode: saved.mode,
            symbol: saved.symbol, speedKmh: 75, routeName: saved.routeName, coordinates: saved.coordinates,
            distance: saved.distance, expectedTravelTime: saved.expectedTravelTime, trafficLabel: saved.trafficLabel,
            finish: .init(action: .stay), date: Date(), departureAirport: nil, arrivalAirport: nil)
        precondition(store.record(replay))
        precondition(store.entries.count == 50 && store.entries[0].id == saved.id && store.entries[0].speedKmh == 75)
        let reopened = RouteHistoryStore(url: url)
        precondition(reopened.entries.map(\.id) == store.entries.map(\.id))
        precondition(reopened.entries[0].finish.action == .stay)
        let backupPolicy = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        precondition(backupPolicy.isExcludedFromBackup == true)
        precondition(reopened.delete(saved.id))
        precondition(reopened.entries.count == 49 && !reopened.entries.contains { $0.id == saved.id })
        precondition(RouteHistoryStore(url: url).entries.count == 49)
        precondition(reopened.clear() && reopened.entries.isEmpty && RouteHistoryStore(url: url).entries.isEmpty)
        try Data("corrupt".utf8).write(to: url)
        let corrupt = RouteHistoryStore(url: url)
        precondition(corrupt.error != nil && !corrupt.record(entry(99)))
        let preserved = try Data(contentsOf: url)
        precondition(preserved == Data("corrupt".utf8))
        precondition(corrupt.clear() && corrupt.record(entry(99)))
        print("PASS: local history, all modes, newest first, deduplication, 50-entry cap, delete, confirmed-clear storage, relaunch, backup exclusion and corrupt-file preservation")
    }
}
