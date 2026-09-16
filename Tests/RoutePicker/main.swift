import Foundation
import MapKit

let suite = "RoutePickerTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let store = RouteRecentPlaces(defaults: defaults)
assert(store.places.isEmpty)
for index in 0..<15 {
    store.remember(RoutePlace(name: "Place \(index)", coordinate:
        CLLocationCoordinate2D(latitude: 48 + Double(index) * 0.001, longitude: 2)))
}
assert(store.places.count == 12 && store.places.first?.name == "Place 14")
store.remember(RoutePlace(name: "Renamed place", coordinate: store.places[3].coordinate))
assert(store.places.count == 12 && store.places.first?.name == "Renamed place")
let restored = RouteRecentPlaces(defaults: defaults)
assert(restored.places.map(\.id) == store.places.map(\.id))
restored.remove(restored.places[0])
assert(RouteRecentPlaces(defaults: defaults).places.count == 11)
restored.remember(RoutePlace(name: "Invalid", coordinate: CLLocationCoordinate2D(latitude: 100, longitude: 2)))
assert(restored.places.count == 11)
defaults.set(Data("broken data".utf8), forKey: "routeRecentPlaces.v1")
assert(RouteRecentPlaces(defaults: defaults).places.isEmpty)
print("PASS: recent-place limit, ordering, deduplication, persistence, removal, invalid coordinates, corrupt data")

func savedBookmarks() -> [[String: Any]] { try! BookMarkRetrieve() }

// Production operations use an isolated file, never a developer's saved places.
defer { try? FileManager.default.removeItem(at: qaFavoriteDirectory) }
assert(RouteFavoritePlaces.places(from: savedBookmarks()).isEmpty)
assert(BookMarkSave(lat: 44.817059, long: -0.585746, name: "Café préféré"))
assert(BookMarkSave(lat: 39.9087, long: 116.3975, name: "Beijing"))
let favorites = RouteFavoritePlaces.places(from: savedBookmarks())
assert(favorites.map(\.name) == ["Café préféré", "Beijing"])
assert(favorites[0].latitude == 44.817059 && favorites[0].longitude == -0.585746)
let china = favorites[1].coordinate
assert(abs(china.longitude - 116.3975) > 0.001, "Chinese favorites must enter map space")
let injected = CoordTransform.gcj02ToWgs84(china)
assert(CLLocation(latitude: injected.latitude, longitude: injected.longitude).distance(
    from: CLLocation(latitude: 39.9087, longitude: 116.3975)) < 3,
    "Picker selection must return to the original WGS-84 position when injected")
assert(RouteFavoritePlaces.matching(favorites, query: "  ").count == 2)
assert(RouteFavoritePlaces.matching(favorites, query: " CAFE ").first?.name == "Café préféré")
assert(RouteFavoritePlaces.matching(favorites, query: "beij").first?.name == "Beijing")
assert(RouteFavoritePlaces.matching(favorites, query: "44.817").isEmpty, "Filter by name, not coordinates")
let malformed: [[String: Any]] = [
    ["name": "Invalid", "lat": 91.0, "long": 0.0], ["name": "Missing"],
    ["name": " ", "lat": 0.0, "long": 0.0]
]
assert(RouteFavoritePlaces.places(from: malformed).map(\.name) == ["Favorite"])
assert(BookMarkSave(lat: 48.85, long: 2.35, name: "Added later"))
assert(RouteFavoritePlaces.places(from: savedBookmarks()).last?.name == "Added later")
assert((savedBookmarks()[1]["long"] as? Double) == 116.3975, "Reading must never rewrite saved coordinates")
print("PASS: shared favorites storage; fresh reload; name/accent filtering; invalid entries; WGS-84 and China selection round trip")

let searchResult = RoutePlace(name: "Pasted location", address: "44.817059, -0.585746",
    coordinate: CLLocationCoordinate2D(latitude: 44.817059, longitude: -0.585746))
assert(FavoritePlaceSave.save(searchResult, name: "  Saved search  "))
let mapPin = RoutePlace(name: "Map pin", coordinate: china)
assert(FavoritePlaceSave.save(mapPin, name: "Saved map pin"))
let saved = savedBookmarks()
assert(saved[saved.count - 2]["name"] as? String == "Saved search")
assert(saved[saved.count - 2]["lat"] as? Double == searchResult.latitude)
assert(saved.last?["name"] as? String == "Saved map pin")
assert(abs((saved.last?["long"] as? Double ?? 0) - 116.3975) < 0.00003,
       "Map pin must be saved in WGS-84, without moving the selected coordinate")
var writes = 0
assert(!FavoritePlaceSave.save(mapPin, name: " \n ") { _, _, _ in writes += 1; return true })
assert(!FavoritePlaceSave.save(RoutePlace(name: "Invalid", coordinate: CLLocationCoordinate2D(latitude: 100, longitude: 0)),
    name: "Invalid") { _, _, _ in writes += 1; return true })
assert(writes == 0, "Invalid favorite input must not write")
assert(!FavoritePlaceSave.save(mapPin, name: "Failure") { _, _, _ in false }, "Storage failure must not report success")
assert(savedBookmarks().count == saved.count, "Invalid saves must leave existing favorites untouched")
print("PASS: editable favorites from search result and map pin, shared persistence, China conversion, invalid input and failed storage")
