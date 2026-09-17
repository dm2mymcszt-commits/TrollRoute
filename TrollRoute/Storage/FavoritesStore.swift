import Foundation

/// All writers use one locked collection. A receipt survives deletion, so a
/// delayed duplicate share cannot silently recreate a favorite the user removed.
struct FavoritesStore {
    struct Favorite: Codable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let latitude: Double
        let longitude: Double
        var valid: Bool {
            latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
        }
        var values: [String: Any] { ["name": name, "lat": latitude, "long": longitude] }
        var dictionary: [String: Any] { values.merging(["id": id.uuidString]) { _, new in new } }
        func samePlace(as other: Favorite) -> Bool {
            name == other.name && latitude == other.latitude && longitude == other.longitude
        }
        init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
            self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
        }
        init(_ value: [String: Any]) throws {
            guard let name = value["name"] as? String, let lat = value["lat"] as? Double,
                  let lon = value["long"] as? Double else { throw Failure.invalidData }
            self.init(id: (value["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
                      name: name, latitude: lat, longitude: lon)
            guard valid else { throw Failure.invalidData }
        }
    }
    enum Failure: LocalizedError {
        case unavailable, invalidData, conflictingRequest
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Couldn't access Favorites. Try opening TrollRoute once, then try again."
            case .invalidData: return "Couldn't read saved Favorites. The existing data has not been changed."
            case .conflictingRequest: return "This save request already belongs to another favorite. Try sharing again."
            }
        }
    }
    // Module visibility avoids a Swift 6.1 IR linkage failure when a different
    // source file passes this store as an optional value. The file stays private.
    struct State: Codable {
        var initialized = false
        var favorites: [Favorite] = []
        var receipts: [UUID: Favorite] = [:]
    }
    private let file: SharedStateFile<State>
    private let legacy: () throws -> [[String: Any]]

    static var shared: FavoritesStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedPreferences.suite).map {
            FavoritesStore(url: $0.appendingPathComponent("Favorites/collection.v1.json"), legacy: {
                guard let value = SharedPreferences.defaults.object(forKey: "bookmarks") else { return [] }
                guard let entries = value as? [[String: Any]] else { throw Failure.invalidData }
                return entries
            })
        }
    }
    init(url: URL, legacy: @escaping () throws -> [[String: Any]] = { [] }) {
        file = SharedStateFile(url: url, initial: { State() })
        self.legacy = legacy
    }
    func read() throws -> [Favorite] { try change { $0.favorites } }
    @discardableResult
    func save(_ favorite: Favorite) throws -> Bool {
        guard favorite.valid else { throw Failure.invalidData }
        return try change { state in
            if let receipt = state.receipts[favorite.id] {
                guard receipt == favorite else { throw Failure.conflictingRequest }
                return false
            }
            guard !state.favorites.contains(where: { $0.id == favorite.id }) else { throw Failure.conflictingRequest }
            state.favorites.append(favorite)
            state.receipts[favorite.id] = favorite
            return true
        }
    }
    func remove(ids: Set<UUID>) throws {
        try change { state in state.favorites.removeAll { ids.contains($0.id) } }
    }
    /// Used by the read-only old-app importer after it validates the full import.
    /// Merge under the same lock as extension saves, never replace a stale array.
    @discardableResult
    func mergeImported(_ values: [[String: Any]]) throws -> Int {
        let candidates = try values.map(Favorite.init)
        return try change { state in
            var count = 0
            for favorite in candidates where !state.favorites.contains(where: { $0.samePlace(as: favorite) }) {
                state.favorites.append(favorite); count += 1
            }
            return count
        }
    }
    private func change<Result>(_ body: (inout State) throws -> Result) throws -> Result {
        try file.update { state in
            if !state.initialized {
                state.favorites = try legacy().map(Favorite.init)
                state.initialized = true
            }
            guard state.favorites.allSatisfy(\.valid), Set(state.favorites.map(\.id)).count == state.favorites.count,
                  state.receipts.allSatisfy({ $0.key == $0.value.id && $0.value.valid }) else { throw Failure.invalidData }
            return try body(&state)
        }
    }
}
