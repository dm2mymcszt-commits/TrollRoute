import Foundation
import CoreFoundation

struct MigrationSummary: Codable, Equatable {
    var favorites = 0
    var recents = 0
    var settings = 0
    var afterRoutePlace = 0
    var foundOldData = false
}

enum MigrationError: LocalizedError {
    case unreadable(String)
    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): return "Could not finish the optional import. \(detail) Your existing data has not been erased. You can continue using TrollRoute."
        }
    }
}

/// Only the new group is writable. Old domains are read as immutable plist bytes;
/// no old UserDefaults suite is opened or synchronized, and no container is created.
enum LegacyMigration {
    static let completionKey = "legacyMigration.v1.completed"
    static let summaryKey = "legacyMigration.v1.summary"
    static let acknowledgedKey = "legacyMigration.v1.acknowledged"
    static let skippedKey = "legacyMigration.v1.skipped"

    static func needsImport(in target: UserDefaults) -> Bool {
        !target.bool(forKey: completionKey) && !target.bool(forKey: acknowledgedKey) &&
            !target.bool(forKey: skippedKey)
    }
    static let settingsKeys = ["routeFinishAction", "routeFinishDestination", "routeRecentPlaces.v1",
        "routeSpeedKmh.walking", "routeSpeedKmh.cycling", "routeSpeedKmh.driving", "altitudeProfile",
        "mapAppearance", "mapStyle", "mapButtonLabels", "mapHaptics", "tapMapToSetLocation", "askBeforeMoving"]

    static func pendingSummary(in target: UserDefaults) -> MigrationSummary? {
        guard target.bool(forKey: completionKey), !target.bool(forKey: acknowledgedKey),
              !target.bool(forKey: skippedKey) else { return nil }
        return target.data(forKey: summaryKey).flatMap { try? JSONDecoder().decode(MigrationSummary.self, from: $0) }
    }

    static func readPlist(_ url: URL) throws -> [String: Any]? {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) { return nil }
        catch { throw MigrationError.unreadable("The saved preferences could not be read.") }
        guard let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = value as? [String: Any] else {
            throw MigrationError.unreadable("The saved preferences are not a valid property list.")
        }
        return dictionary
    }

    static func run(preferenceURLs: [URL], favoritesURL: URL?, oldAppInstalled: Bool,
                    target: UserDefaults, favoriteStore: FavoritesStore) throws -> MigrationSummary? {
        if !needsImport(in: target) { return pendingSummary(in: target) }
        // Uninstalling the old app ends the optional import. Do not read orphaned
        // containers, replay a journal, or require any preference writes to open.
        guard oldAppInstalled else { return nil }
        // The old app has no-container: its global domain takes precedence. A
        // container plist is used only if that global plist does not exist.
        var preferences: [String: Any]?
        for url in preferenceURLs {
            if let values = try readPlist(url) { preferences = values; break }
        }
        let favorites = try favoritesURL.flatMap { try readPlist($0) }
        if oldAppInstalled && (preferences == nil || favoritesURL == nil) {
            throw MigrationError.unreadable("Its saved preferences or Favorites container could not be located.")
        }
        if preferences == nil && favorites?["bookmarks"] != nil {
            throw MigrationError.unreadable("Favorites were found, but the old app's settings could not be located.")
        }
        var summary = MigrationSummary()
        summary.foundOldData = preferences != nil || favorites?["bookmarks"] != nil
        let imported = try validated(preferences ?? [:], favorites: favorites ?? [:])
        var writes: [String: Any] = [:]
        for (key, value) in imported {
            if key == "bookmarks", let old = value as? [[String: Any]] {
                var combined = try favoriteStore.read().map(\.values)
                for item in old where !combined.contains(where: { NSDictionary(dictionary: $0).isEqual(to: item) }) {
                    combined.append(item); summary.favorites += 1
                }
                writes[key] = old
            } else if key == "routeRecentPlaces.v1", let data = value as? Data {
                var combined = (target.data(forKey: key).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]) ?? []
                let old = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
                for item in old where !combined.contains(where: {
                    $0["latitude"] as? Double == item["latitude"] as? Double &&
                    $0["longitude"] as? Double == item["longitude"] as? Double
                }) { combined.append(item); summary.recents += 1 }
                // Preserve every original field (including UUID and map-coordinate format).
                writes[key] = try JSONSerialization.data(withJSONObject: combined, options: [.sortedKeys])
            } else if target.object(forKey: key) == nil {
                writes[key] = value
                if key == "routeFinishDestination" { summary.afterRoutePlace = try decodePlace(value) == nil ? 0 : 1 }
                else { summary.settings += 1 }
            }
        }
        // A durable journal gives interrupted launches the same summary and prevents
        // a crash between copying values and setting completion from losing counts.
        let journalKey = "legacyMigration.v1.journal"
        if let journal = target.dictionary(forKey: journalKey),
           let saved = journal["summary"] as? Data, let savedWrites = journal["values"] as? [String: Any] {
            summary = try JSONDecoder().decode(MigrationSummary.self, from: saved)
            // A Favorite may have been added from the extension between launches.
            // Keep the freshly merged collections instead of restoring an old array.
            let collections = writes.filter { ["bookmarks", "routeRecentPlaces.v1"].contains($0.key) }
            writes = savedWrites.merging(collections) { _, current in current }
        } else {
            target.set(["summary": try JSONEncoder().encode(summary), "values": writes], forKey: journalKey)
            guard target.synchronize() else { throw MigrationError.unreadable("TrollRoute's import journal could not be saved.") }
        }
        // Do not replace a previously read Favorites array: the extension can
        // save while import runs. Merge old-app candidates under the store lock.
        if let favorites = writes["bookmarks"] as? [[String: Any]] {
            try favoriteStore.mergeImported(favorites)
        }
        for (key, value) in writes where key != "bookmarks" { target.set(value, forKey: key) }
        // Commit completion only after new data has reached its persistent domain.
        guard target.synchronize() else { throw MigrationError.unreadable("TrollRoute's imported preferences could not be saved.") }
        target.set(try JSONEncoder().encode(summary), forKey: summaryKey)
        target.set(true, forKey: completionKey)
        if !summary.foundOldData { target.set(true, forKey: acknowledgedKey) }
        guard target.synchronize() else {
            target.removeObject(forKey: completionKey)
            throw MigrationError.unreadable("TrollRoute's import completion could not be saved.")
        }
        target.removeObject(forKey: journalKey)
        return summary.foundOldData ? summary : nil
    }

    private struct SavedPlace: Decodable {
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
    }

    private static func valid(_ lat: Double, _ lon: Double) -> Bool {
        lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
    }
    private static func decodePlaces(_ value: Any) throws -> [SavedPlace] {
        guard let data = value as? Data, let places = try? JSONDecoder().decode([SavedPlace].self, from: data),
              places.allSatisfy({ valid($0.latitude, $0.longitude) }) else { throw invalid("Recent Places") }
        guard let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              objects.allSatisfy({ ($0["id"] as? String).flatMap(UUID.init(uuidString:)) != nil }) else { throw invalid("Recent Places IDs") }
        // Recents are already map coordinates, unlike Favorites and after-route place.
        return places
    }
    private static func decodePlace(_ value: Any) throws -> SavedPlace? {
        guard let data = value as? Data else { throw invalid("after-route place") }
        do {
            let place = try JSONDecoder().decode(SavedPlace?.self, from: data)
            if let place = place, !valid(place.latitude, place.longitude) { throw invalid("after-route place") }
            return place
        } catch { throw invalid("after-route place") }
    }
    private static func invalid(_ key: String) -> MigrationError {
        .unreadable("The saved \(key) value is invalid.")
    }
    static func validated(_ preferences: [String: Any], favorites: [String: Any]) throws -> [String: Any] {
        var values = preferences.filter { settingsKeys.contains($0.key) }
        if let bookmarks = favorites["bookmarks"] {
            guard let list = bookmarks as? [[String: Any]], list.allSatisfy({ item in
                guard item["name"] is String, let lat = item["lat"] as? Double,
                      let lon = item["long"] as? Double else { return false }
                return valid(lat, lon)
            }) else { throw invalid("Favorites") }
            values["bookmarks"] = list
        }
        for (key, value) in values {
            switch key {
            case "bookmarks": break
            case "routeRecentPlaces.v1": _ = try decodePlaces(value)
            case "routeFinishDestination": _ = try decodePlace(value)
            case "routeFinishAction":
                guard let action = value as? String,
                      ["stay", "goToPlace", "stop", "loop", "returnOnce", "backAndForth"].contains(action) else { throw invalid(key) }
            case "mapAppearance", "mapStyle":
                let allowed = key == "mapAppearance" ? ["system", "light", "dark"] : ["standard", "hybrid"]
                guard let text = value as? String, allowed.contains(text) else { throw invalid(key) }
            case "mapButtonLabels", "mapHaptics", "tapMapToSetLocation", "askBeforeMoving":
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw invalid(key) }
            case "altitudeProfile":
                struct Profile: Decodable { let mode: String; let customMeters: Double }
                guard let data = value as? Data, let profile = try? JSONDecoder().decode(Profile.self, from: data),
                      ["automatic", "custom"].contains(profile.mode), profile.customMeters.isFinite else { throw invalid(key) }
            default:
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, (1...500).contains(number.doubleValue) else { throw invalid(key) }
            }
        }
        return values
    }
}
