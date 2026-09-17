import Foundation
import CoreLocation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
// Child processes exercise the real file lock and Darwin channel, not a mock mutex.
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--enqueue" {
    let childInbox = SharedPlaceInbox(container: URL(fileURLWithPath: CommandLine.arguments[2]))
    let childPlace = RoutePlace(name: CommandLine.arguments[3], coordinate: CLLocationCoordinate2D(latitude: 44.8, longitude: -0.6))
    try childInbox.enqueue(SharedPlaceRequest(place: childPlace, action: .start))
    exit(0)
}
if CommandLine.arguments.contains("--signal") { SharedPlaceSignal.post(); exit(0) }

let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let inbox = SharedPlaceInbox(container: container)
defer { try? FileManager.default.removeItem(at: container) }
let wgs = CLLocationCoordinate2D(latitude: 39.9087, longitude: 116.3975)
let map = CoordTransform.wgs84ToGcj02(wgs)
let place = RoutePlace(name: "Shared favorite", address: "Test address", coordinate: map)
var requests: [SharedPlaceRequest] = []
for action in SharedPlaceAction.allCases {
    let request = SharedPlaceRequest(place: place, action: action)
    try inbox.enqueue(request)
    requests.append(request)
    require(abs(request.latitude - wgs.latitude) < 0.00003 && abs(request.longitude - wgs.longitude) < 0.00003, "Inbox must store WGS-84")
}
let reopened = SharedPlaceInbox(container: container)
require(reopened.pending().count == 4, "All actions survive reopening")
require(Set(reopened.pending().map(\.action)) == Set(SharedPlaceAction.allCases), "Shared actions lost")
for request in reopened.pending() {
    let converted = request.place!.coordinate
    require(abs(converted.latitude - map.latitude) < 0.00003 && abs(converted.longitude - map.longitude) < 0.00003, "Map-space round trip changed the place")
}
try reopened.remove(requests[1])
require(reopened.pending().count == 3 && !reopened.pending().contains(where: { $0.id == requests[1].id }), "Cancel removes only its own action")
try Data("malformed".utf8).write(to: inbox.directory!.appendingPathComponent("bad.json"))
require(reopened.pending().count == 3, "Malformed payload must not hide valid queued places")
let draft = RouteDraft()
draft.accept(requests[1])
draft.accept(requests[2])
require(draft.start?.name == place.name && draft.destination?.name == place.name && draft.needsRecalculation, "Separate Start and Destination shares must preserve both endpoints")
let previousStart = draft.start?.id
draft.accept(requests[0])
require(draft.start?.id == previousStart, "A Go request must not edit the route draft")
let resolvedCurrent = RoutePlace(name: "Current Location", coordinate: CLLocationCoordinate2D(latitude: 44.8, longitude: -0.6))
draft.start = resolvedCurrent
draft.destination = place
require(draft.swapEndpoints(), "Resolved endpoints can swap")
require(draft.destination?.id == resolvedCurrent.id && draft.destination?.latitude == 44.8 && draft.start?.id == place.id,
        "Swap must preserve the resolved current-location coordinates and both names")
require(draft.swapEndpoints() && draft.start?.id == resolvedCurrent.id && draft.destination?.id == place.id, "Swap twice restores endpoints")
draft.start = nil
require(!draft.swapEndpoints() && draft.destination?.id == place.id, "Unresolved current location cannot swap")
let favoriteStore = FavoritesStore(url: container.appendingPathComponent("favorites.json"))
let favoriteID = UUID()
try SharedPlaceInbox.saveFavorite(place, id: favoriteID, store: favoriteStore)
try SharedPlaceInbox.saveFavorite(place, id: favoriteID, store: favoriteStore)
let favorites = RouteFavoritePlaces.places(from: try favoriteStore.read().map(\.dictionary))
require(favorites.count == 1 && favorites[0].name == place.name, "App and extension must share one store without duplicate retries")
require(abs(favorites[0].latitude - map.latitude) < 0.00003 && abs(favorites[0].longitude - map.longitude) < 0.00003, "Shared favorite must convert exactly once")
try favoriteStore.remove(ids: [favoriteID])
try SharedPlaceInbox.saveFavorite(place, id: favoriteID, store: favoriteStore)
let afterDeletedRetry = try favoriteStore.read()
require(afterDeletedRetry.isEmpty, "A delayed accepted share must not recreate a deleted favorite")
do { try SharedPlaceInbox.saveFavorite(place, store: nil); fatalError("Missing group must not report saved") }
catch FavoritesStore.Failure.unavailable { }
print("PASS: four share actions, durable inbox, cancellation, invalid payloads, independent endpoints and WGS-84 Favorites")
for autoStart in [false, true] {
    draft.prepareFromMap(start: resolvedCurrent, destination: place, autoStart: autoStart)
    require(draft.needsRecalculation && draft.start?.id == resolvedCurrent.id && draft.destination?.id == place.id,
            "Long press must fill both Navigation endpoints")
    require(draft.takeAutomaticPreparation() == autoStart && draft.takeAutomaticPreparation() == nil,
            "Opening Navigation must calculate once, and never repeat auto-start after reopening")
}
draft.prepareFromMap(start: resolvedCurrent, destination: place, autoStart: true)
draft.accept(requests[2])
require(draft.takeAutomaticPreparation() == nil, "A later shared endpoint must invalidate earlier auto-start intent")

for (input, expected) in [
    ("https://maps.app.goo.gl/abc", SharedPlaceSource.googleMaps),
    ("Place name https://goo.gl/maps/abc", .googleMaps),
    ("https://www.google.fr/maps/place/Test", .googleMaps),
    ("https://maps.google.co.uk/?q=44,-0.6", .googleMaps),
    ("https://consent.google.com/m?continue=https%3A%2F%2Fwww.google.com%2Fmaps%2Fplace%2FTest", .googleMaps),
    ("https://maps.apple.com/?ll=44,-0.6", .appleMaps),
    ("44.8, -0.6", .text),
    ("Google Maps, a shop name", .text),
    ("https://maps.google.com.example.org/maps", .text),
    ("https://google.com/search?q=maps", .text),
    ("https://consent.google.com/m?continue=https%3A%2F%2Fexample.org", .text)
] { require(SharedPlaceSource.detect(input) == expected, "Incorrect shared source: " + input) }
var googlePlace = place
googlePlace.sharedSource = .googleMaps
let sourced = SharedPlaceRequest(place: googlePlace, action: .start)
let sourceRoundTrip = try JSONDecoder().decode(SharedPlaceRequest.self, from: JSONEncoder().encode(sourced))
require(sourceRoundTrip.sourceTitle == "From Google Maps" && sourceRoundTrip.place?.sharedSource == .googleMaps,
        "Source must survive the shared queue independently of search provider")
draft.accept(sourceRoundTrip)
require(draft.start?.sharedSource == .googleMaps, "Endpoint must retain attachment source")
draft.destination = place
require(draft.swapEndpoints() && draft.destination?.sharedSource == .googleMaps, "Source follows swapped endpoint")
var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sourced)) as! [String: Any]
legacy.removeValue(forKey: "source")
let legacyRequest = try JSONDecoder().decode(SharedPlaceRequest.self, from: JSONSerialization.data(withJSONObject: legacy))
require(legacyRequest.place != nil && legacyRequest.sourceTitle == "Shared place", "Legacy inbox remains readable without fabricated provenance")
var oldPlace = try JSONSerialization.jsonObject(with: JSONEncoder().encode(googlePlace)) as! [String: Any]
oldPlace.removeValue(forKey: "sharedSource")
let decodedOldPlace = try JSONDecoder().decode(RoutePlace.self, from: JSONSerialization.data(withJSONObject: oldPlace))
require(decodedOldPlace.sharedSource == nil,
        "Old recents remain readable")
let recentSuite = "TrollRoute.Share.Recents.Tests." + UUID().uuidString
let defaults = UserDefaults(suiteName: recentSuite)!
defer { defaults.removePersistentDomain(forName: recentSuite) }
let recent = RouteRecentPlaces(defaults: defaults)
recent.remember(googlePlace)
require(RouteRecentPlaces(defaults: defaults).places.first?.sharedSource == .googleMaps, "Recents retain source")
print("PASS: source links/consent/host boundaries, durable provenance, endpoint swaps and legacy decoding")

let commandID = UUID()
require(SharedCommandURL.requestID(SharedCommandURL.make(commandID)) == commandID, "Command URL UUID round trip")
for invalid in ["https://shared/" + commandID.uuidString, "trollroute://other/" + commandID.uuidString,
                "trollroute://shared/not-a-uuid", "trollroute://shared/" + commandID.uuidString + "/extra",
                "trollroute://user@shared/" + commandID.uuidString, "trollroute://shared/" + commandID.uuidString + "?action=go"] {
    require(SharedCommandURL.requestID(URL(string: invalid)!) == nil, "Reject malformed command URL")
}
try inbox.enqueue(sourceRoundTrip)
let applied = try inbox.consumeEndpoint(sourceRoundTrip.id)
require(applied?.start?.sharedSource == .googleMaps && applied?.presentation == sourceRoundTrip.id, "Endpoint and pending presentation commit together")
let duplicate = try inbox.consumeEndpoint(sourceRoundTrip.id)
require(duplicate == nil, "Repeated signal must not handle endpoint twice")
try inbox.enqueue(sourceRoundTrip)
require(!inbox.pending().contains(where: { $0.id == sourceRoundTrip.id }), "Re-enqueue cannot replay handled UUID")
let savedDraft = try SharedPlaceInbox(container: container).routeDraft()
require(savedDraft.start?.name == googlePlace.name && savedDraft.presentation == sourceRoundTrip.id, "Unpresented endpoint survives process restart")
try inbox.acknowledgePresentation(UUID())
require(tryValue { try inbox.routeDraft().presentation } == sourceRoundTrip.id, "Stale UI acknowledgement must not clear new presentation")
try inbox.acknowledgePresentation(sourceRoundTrip.id)
require(tryValue { try inbox.routeDraft().presentation } == nil, "Presented endpoint does not reopen on next launch")
// A pre-upgrade file resurrected after cleanup cannot replay a completed command.
try JSONEncoder().encode(sourceRoundTrip).write(to: inbox.directory!.appendingPathComponent(sourceRoundTrip.id.uuidString + ".json"))
require(!inbox.pending().contains(where: { $0.id == sourceRoundTrip.id }), "Legacy import respects receipts")
let concurrentContainer = container.appendingPathComponent("concurrent")
var writers: [Process] = []
for index in 0..<12 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["--enqueue", concurrentContainer.path, "writer-\(index)"]
    try process.run(); writers.append(process)
}
for process in writers { process.waitUntilExit(); require(process.terminationStatus == 0, "Concurrent writer failed") }
let concurrent = try SharedPlaceInbox(container: concurrentContainer).pendingRequests()
require(concurrent.count == 12 && Set(concurrent.map(\.name)).count == 12, "Cross-process writes must not lose any command")
var signaled = false
let observer = SharedPlaceSignal { signaled = true }
let started = Date()
let sender = Process()
sender.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); sender.arguments = ["--signal"]
try sender.run()
while !signaled && Date().timeIntervalSince(started) < 1 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
}
withExtendedLifetime(observer) { require(signaled, "Cross-process Darwin signal must arrive within 1 second") }
sender.waitUntilExit()
let corruptContainer = container.appendingPathComponent("corrupt")
let corruptInbox = SharedPlaceInbox(container: corruptContainer)
try corruptInbox.enqueue(sourceRoundTrip)
try Data("broken".utf8).write(to: corruptInbox.directory!.appendingPathComponent("ledger.v1.json"))
var rejectedCorruption = false
do { try corruptInbox.enqueue(requests[0]) } catch { rejectedCorruption = true }
require(rejectedCorruption, "A corrupt completion ledger cannot be replaced by an empty queue")
print("PASS: strict URLs, atomic endpoint/receipt, replay/crash recovery, 12 concurrent writers and Darwin event under 1 second")

func tryValue<T>(_ body: () throws -> T) -> T { try! body() }

let endpointOnly = SharedPlaceRequest(place: googlePlace, action: .destination)
try inbox.enqueue(endpointOnly)
let editedBase = SharedRouteDraft(start: resolvedCurrent, destination: nil)
let handoff = try inbox.consumeEndpoint(endpointOnly.id, current: editedBase)!
require(handoff.start?.id == resolvedCurrent.id && handoff.destination?.sharedSource == .googleMaps,
        "A shared endpoint must preserve the other point currently edited in Navigation")
draft.prepareFromMap(start: resolvedCurrent, destination: place, autoStart: true)
draft.applySharedDraft(handoff)
let firstSharedRevision = draft.revision
let replacement = SharedRouteDraft(start: resolvedCurrent, destination: place)
draft.applySharedDraft(replacement)
require(draft.revision != firstSharedRevision, "An external replacement invalidates a retained sheet")
draft.commitEdits(start: nil, destination: nil, revision: firstSharedRevision)
require(draft.start?.id == resolvedCurrent.id && draft.destination?.id == place.id,
        "Closing an older sheet must not overwrite the next shared endpoint")
draft.commitEdits(start: place, destination: resolvedCurrent, revision: draft.revision)
require(draft.start?.id == place.id && draft.destination?.id == resolvedCurrent.id,
        "Edits from the current sheet remain persistent")
draft.applySharedDraft(handoff)
require(draft.destination?.sharedSource == .googleMaps && draft.takeAutomaticPreparation() == nil,
        "An endpoint share must not inherit an old long-press auto-start")
let channel = SharedPlaceChannel()
channel.setActive(false)
channel.wake()
require(!channel.isActive, "A signal does not invent foreground state")
channel.setActive(true)
require(channel.isActive && channel.revision == 2, "Activation consumes the new lifecycle value immediately")
print("PASS: endpoint handoff preserves edited start, cancels stale auto-start and tracks actual lifecycle")
