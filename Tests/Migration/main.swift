import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let files = FileManager.default
let temp = files.temporaryDirectory.appendingPathComponent("TrollRouteMigration-\(UUID())")
try files.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? files.removeItem(at: temp) }
let old = temp.appendingPathComponent("old.plist")
let favorites = temp.appendingPathComponent("favorites.plist")
let fixture = URL(fileURLWithPath: "Tests/Migration/Fixtures")
try files.copyItem(at: fixture.appendingPathComponent("preferences.plist"), to: old)
try files.copyItem(at: fixture.appendingPathComponent("favorites.plist"), to: favorites)
let sourceBytes = try Data(contentsOf: old)
let favoriteBytes = try Data(contentsOf: favorites)
let suite = "TrollRoute.Migration.Tests.\(UUID())"
let target = UserDefaults(suiteName: suite)!
let storeURL = temp.appendingPathComponent("new-favorites.json")
let store = FavoritesStore(url: storeURL)
func storedFavorites() -> [[String: Any]] { try! store.read().map(\.values) }
func resetTarget() {
    target.removePersistentDomain(forName: suite)
    try? files.removeItem(at: storeURL)
}
defer { target.removePersistentDomain(forName: suite) }
let summary = try LegacyMigration.run(preferenceURLs: [old], favoritesURL: favorites, oldAppInstalled: true, target: target, favoriteStore: store)!
require(summary.favorites == 2 && summary.recents == 2 && summary.afterRoutePlace == 1 && summary.settings == 11, "All requested categories counted")
let source = try LegacyMigration.readPlist(old)!
for key in LegacyMigration.settingsKeys where key != "routeRecentPlaces.v1" {
    require(NSDictionary(dictionary: [key: target.object(forKey: key)!]).isEqual(to: [key: source[key]!]), "Preserve \(key) exactly")
}
let recentSource = try JSONSerialization.jsonObject(with: source["routeRecentPlaces.v1"] as! Data) as! NSArray
let recentTarget = try JSONSerialization.jsonObject(with: target.data(forKey: "routeRecentPlaces.v1")!) as! NSArray
require(recentSource == recentTarget, "Recents preserve map coordinates, UUIDs and approximation fields")
let originalFavorites = try LegacyMigration.readPlist(favorites)!["bookmarks"] as! NSArray
require((storedFavorites() as NSArray) == originalFavorites, "Favorites stay WGS-84")
require(target.object(forKey: "obsoleteFeature") == nil && target.object(forKey: "TSBypass") == nil, "Do not import unrelated or bypass keys")
let initialOldBytes = try Data(contentsOf: old)
let initialFavoriteBytes = try Data(contentsOf: favorites)
require(initialOldBytes == sourceBytes && initialFavoriteBytes == favoriteBytes, "Old bytes untouched")
target.set(120, forKey: "routeSpeedKmh.driving")
let repeated = try LegacyMigration.run(preferenceURLs: [old], favoritesURL: favorites, oldAppInstalled: true, target: target, favoriteStore: store)
require(repeated == summary && target.double(forKey: "routeSpeedKmh.driving") == 120, "Completed import never replays")
target.set(true, forKey: LegacyMigration.acknowledgedKey)
require(LegacyMigration.pendingSummary(in: target) == nil, "Summary acknowledged once")

resetTarget()
target.set("dark", forKey: "mapAppearance")
try store.save(.init(name: "New favorite", latitude: 12, longitude: 20))
let merged = try LegacyMigration.run(preferenceURLs: [old], favoritesURL: favorites, oldAppInstalled: true, target: target, favoriteStore: store)!
require(merged.favorites == 2 && storedFavorites().count == 3, "Merge existing new Favorites")
require(target.string(forKey: "mapAppearance") == "dark", "Existing new-app setting wins")

resetTarget()
var corrupt = source
corrupt["routeSpeedKmh.driving"] = true
try PropertyListSerialization.data(fromPropertyList: corrupt, format: .xml, options: 0).write(to: old)
do {
    _ = try LegacyMigration.run(preferenceURLs: [old], favoritesURL: favorites, oldAppInstalled: true, target: target, favoriteStore: store)
    fatalError("Invalid source accepted")
} catch is MigrationError {}
require(storedFavorites().isEmpty && !target.bool(forKey: LegacyMigration.completionKey), "Validate everything before any import writes")
try sourceBytes.write(to: old)
do {
    _ = try LegacyMigration.run(preferenceURLs: [old], favoritesURL: nil, oldAppInstalled: true, target: target, favoriteStore: store)
    fatalError("Missing Favorites container accepted")
} catch is MigrationError {}
let malformed = temp.appendingPathComponent("malformed.plist")
try Data("bad plist".utf8).write(to: malformed)
do { _ = try LegacyMigration.readPlist(malformed); fatalError("Malformed plist accepted") } catch is MigrationError {}
do { _ = try LegacyMigration.readPlist(temp); fatalError("Unreadable source accepted") } catch is MigrationError {}
require(!target.bool(forKey: LegacyMigration.completionKey), "Failures cannot mark import complete")

// Failure of the new store cannot mark migration complete or erase old data.
try Data("broken Favorites".utf8).write(to: storeURL)
do {
    _ = try LegacyMigration.run(preferenceURLs: [old], favoritesURL: favorites, oldAppInstalled: true,
                                target: target, favoriteStore: store)
    fatalError("Corrupt new Favorites accepted")
} catch { }
require(!target.bool(forKey: LegacyMigration.completionKey), "Storage failure cannot complete import")
try files.removeItem(at: storeURL)

// Recovery after data was copied but before completion, without double counts.
let journalSummary = MigrationSummary(favorites: 2, recents: 2, settings: 11, afterRoutePlace: 1, foundOldData: true)
target.set(["values": ["routeSpeedKmh.driving": 91], "summary": try JSONEncoder().encode(journalSummary)], forKey: "legacyMigration.v1.journal")
// An extension save between interrupted launches must survive journal recovery.
try store.save(.init(name: "Saved from extension", latitude: 20, longitude: 30))
let recovered = try LegacyMigration.run(preferenceURLs: [old], favoritesURL: favorites, oldAppInstalled: true, target: target, favoriteStore: store)
require(recovered == journalSummary && target.integer(forKey: "routeSpeedKmh.driving") == 91, "Interrupted import journal recovered")
require(target.object(forKey: "legacyMigration.v1.journal") == nil, "Finished journal removed")
require(storedFavorites().count == 3 && storedFavorites().contains { $0["name"] as? String == "Saved from extension" },
        "Recovered import merges without discarding an extension save")
resetTarget()
let absent = temp.appendingPathComponent("absent.plist")
let none = try LegacyMigration.run(preferenceURLs: [absent], favoritesURL: nil, oldAppInstalled: false, target: target, favoriteStore: store)
require(none == nil && target.bool(forKey: LegacyMigration.completionKey), "Fresh installation completes without a false imported-data summary")
let finalOldBytes = try Data(contentsOf: old)
let finalFavoriteBytes = try Data(contentsOf: favorites)
require(finalOldBytes == sourceBytes && finalFavoriteBytes == favoriteBytes, "All tests leave source bytes intact")
print("PASS: read-only migration, all settings, coordinates, merging, once-only summary, failures and interrupted recovery")
