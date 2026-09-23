import Foundation
import CoreLocation
import MapKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func coordinate(_ metersEast: Double) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: 0, longitude: metersEast / 111_319.49079327358)
}

func near(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.005) -> Bool {
    abs(lhs - rhs) <= tolerance
}

// Production distance engine: irregular ticks, seeks, speed changes, and motion.
let shortSegments = (0...100).map { coordinate(Double($0)) }
let track = RouteTrack(coordinates: shortSegments)!
require(near(track.length, 100), "Short segments must preserve total length")
let duplicateTrack = RouteTrack(coordinates: [coordinate(0), coordinate(0), coordinate(3), coordinate(3), coordinate(100)])!
require(duplicateTrack.coordinates.count == 3 && near(duplicateTrack.length, 100), "Duplicate vertices must not consume distance")
require(RouteTrack(coordinates: []) == nil, "Reject empty track")
require(RouteTrack(coordinates: [coordinate(0), coordinate(0)]) == nil, "Reject stationary route")
require(RouteTrack(coordinates: [coordinate(0), CLLocationCoordinate2D(latitude: 91, longitude: 0)]) == nil, "Reject invalid coordinates")
var trip = RouteJourney(track: track, speedKmh: 36)
for seconds in [0.1, 0.3, 0.6, 1.4, 0.6] { trip.advance(seconds: seconds) }
require(near(trip.distance, 30) && near(trip.elapsed, 3), "Actual elapsed time, not tick count, controls distance")
require(near(trip.motion(paused: false).course, 90), "Course points to the next segment")
require(near(trip.motion(paused: false).speed, 10), "Moving speed matches trip speed exactly")
require(trip.motion(paused: true).speed == 0, "Paused motion must be stationary")
trip.seek(0.05)
trip.seek(0.46)
require(near(trip.distance, 46), "Seek from five to forty-six percent")
require(near(RouteSimulationMath.distance(trip.motion(paused: false).coordinate, coordinate(46)), 0), "Seek updates the actual model coordinate")
trip.seek(0.1)
require(near(trip.distance, 10), "Seek backwards")
trip.changeSpeed(120)
trip.advance(seconds: 1)
require(near(trip.distance, 10 + 120 / 3.6), "120 km/h applies to the next elapsed step")
require(near(trip.motion(paused: false).speed, 120 / 3.6), "120 km/h is injected, not the old speed")
trip.changeSpeed(50)
require(near(trip.remainingSeconds, trip.remainingDistance / (50 / 3.6)), "Remaining time reacts immediately to speed")
trip.seek(1)
require(trip.isFinished && trip.motion(paused: false).speed == 0, "Seeking to 100 percent finishes with zero speed")
require(near(RouteSimulationMath.distance(trip.motion(paused: false).coordinate, coordinate(100)), 0), "Exact destination")
trip.seek(0.9)
trip.advance(seconds: 60)
require(trip.isFinished && trip.remainingSeconds == 0, "Overshoot clamps exactly to the destination")
let previousDistance = trip.distance
trip.seek(.nan)
trip.advance(seconds: .infinity)
require(trip.distance == previousDistance, "Non-finite seek/tick values cannot corrupt a route")
let dateLine = RouteTrack(coordinates: [CLLocationCoordinate2D(latitude: 0, longitude: 179.999),
                                      CLLocationCoordinate2D(latitude: 0, longitude: -179.999)])!
require(abs(dateLine.position(at: dateLine.length / 2).coordinate.longitude) > 179.99, "Date-line seeking must take the short direction")

// The simulated duration belongs to each route; provider traffic ETA remains separate.
let speed = 75.0 / 3.6
let etas = [24_100.0, 24_300.0, 13_200.0].map {
    RouteSimulationMath.durationText(RouteSimulationMath.simulationSeconds(distance: $0, speed: speed))
}
require(Set(etas).count == 3, "Routes with different distances must have different simulated durations")
require(RouteSimulationMath.simulationSeconds(distance: 100, speed: 0) == nil, "Zero speed has no duration")
require(RouteSimulationMath.durationText(3_600) == "1h 0m", "One-hour boundary")
require(RouteSimulationMath.durationText(.nan) == "Unavailable", "Non-finite duration")
require(RouteSimulationMath.durationText(60.01) == "1m 1s", "Round remaining partial seconds up")
require(RouteSimulationMath.rankedIndices(distances: [24_300, 24_100, 13_200]) == [2, 1, 0],
        "Fastest must follow simulated duration: shortest at the same speed")
require(RouteSimulationMath.rankedIndices(distances: [.nan, 0, 20, 10]) == [3, 2, 0, 1], "Invalid distance must sort last")
require(RouteSimulationMath.rankedIndices(distances: [10, 10]) == [0, 1], "Stable ranking tie")
require(RouteSimulationMath.durationText(RouteSimulationMath.simulationSeconds(distance: 7_900, speed: 500 / 3.6)) == "57s", "7.9 km at 500 km/h must show 57 seconds")
require(RouteSimulationMath.durationText(RouteSimulationMath.simulationSeconds(distance: 7_500, speed: 500 / 3.6)) == "54s", "7.5 km is faster than 7.9 km")
print("PASS: distance-based travel, irregular ticks, seek forward/back/end, live speed and motion metadata, date line, per-route durations, simulation-speed ranking")

let suiteName = "TrollRoute.RouteSpeeds.Tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
defer { defaults.removePersistentDomain(forName: suiteName) }
var speeds = RouteSpeeds(defaults: defaults)
require(speeds[.walking] == 5 && speeds[.cycling] == 20 && speeds[.driving] == 50, "Exact default km/h for each mode")
for mode in TravelMode.allCases {
    speeds.set(1, for: mode)
    require(RouteSpeeds(defaults: defaults)[mode] == 1, "Persist minimum speed in every mode")
    speeds.set(500, for: mode)
    require(RouteSpeeds(defaults: defaults)[mode] == 500, "Persist maximum speed in every mode")
}
speeds.set(7, for: .walking)
speeds.set(26, for: .cycling)
speeds.set(120, for: .driving)
let restored = RouteSpeeds(defaults: defaults)
require(restored[.walking] == 7 && restored[.cycling] == 26 && restored[.driving] == 120, "Mode speeds must remain independent across launches")
speeds.set(.nan, for: .walking)
require(speeds[.walking] == 7, "Reject non-finite speed")
require(TravelMode.cycling.appleTransportType == nil, "Cycling must not request walking directions")

func path(_ distance: Double, offset: Double = 0) -> RoutePath {
    let coords = [coordinate(offset), coordinate(offset + distance)]
    return RoutePath(polyline: MKPolyline(coordinates: coords, count: coords.count), distance: distance,
                     expectedTravelTime: distance / 10, name: "Fixture")
}
var cache = RouteModeCache()
cache.store([path(7_900), path(7_500)], for: .driving)
cache.store([path(6_000, offset: 100), path(5_000, offset: 100)], for: .cycling)
cache.store([path(4_000, offset: 200)], for: .walking)
let original = cache.routes[.driving]![0].route.polyline
require(cache.duration(for: .driving, kmh: 500) == "54s", "Mode tab shows shortest simulated time")
cache.select(1, for: .driving)
cache.select(1, for: .cycling)
require(cache.selections[.driving] == 1 && cache.selections[.cycling] == 1, "Mode switches preserve independent alternative selections")
require(cache.routes[.driving]![0].route.polyline === original, "Switching mode must reuse cached geometry")
require(cache.duration(for: .driving, kmh: 250) == "1m 48s", "Speed changes update mode duration without replacing routes")
cache = RouteModeCache()
require(cache.routes.isEmpty && cache.selections.isEmpty, "Changing endpoints clears every mode")

let bicycleJSON = #"{"code":"Ok","routes":[{"geometry":{"coordinates":[[-0.585746,44.817059],[-0.59,44.82]]},"distance":720,"duration":150,"legs":[{"summary":"Cycleway"}]}]}"#.data(using: .utf8)!
let bicycle = try! BicycleDirections.decode(bicycleJSON)[0]
require(bicycle.distance == 720 && bicycle.name == "Cycleway", "Decode bicycle distance and road name")
require(bicycle.polyline.pointCount == 2 && near(bicycle.polyline.coordinate.latitude, 44.817059, tolerance: 0.01), "Decode GeoJSON longitude/latitude order")
do {
    _ = try BicycleDirections.decode(Data(#"{"code":"NoRoute"}"#.utf8))
    fatalError("NoRoute must be reported, not replaced by walking")
} catch {}
print("PASS: per-mode speed persistence/range, independent route cache, bicycle provider decoding")

for (action, expected) in [(RouteFinishAction.stay, RouteFinishEffect.hold), (.goToPlace, .goToPlace), (.stop, .stop)] {
    var finish = RouteFinishState(action: action)
    let arrival = finish.arrive()
    require(arrival.effect == expected && arrival.notification != nil, "Single arrival action and notification")
}
var loop = RouteFinishState(action: .loop)
require(loop.legName == "Lap 1", "Initial lap label")
for leg in 1...10 {
    let arrival = loop.arrive()
    require(arrival.effect == .restart && (arrival.notification != nil) == (leg == 1), "Loop notifies only on its first arrival")
}
require(loop.legName == "Lap 11", "Loop progress identifies the current lap")
var returnTrip = RouteFinishState(action: .returnOnce)
require(returnTrip.arrive().effect == .reverse && returnTrip.legName == "Returning to start", "Return trip uses a reverse leg")
let home = returnTrip.arrive()
require(home.effect == .hold && home.notification == "Staying at the start", "Return trip notifies again and stays at its start")
var repeated = RouteFinishState(action: .backAndForth)
for leg in 1...6 {
    let arrival = repeated.arrive()
    require(arrival.effect == .reverse && repeated.returning == (leg % 2 == 1), "Repeated trips alternate directions")
    require((arrival.notification != nil) == (leg == 1), "Repeated trips do not notify every leg")
}
repeated.skipRepeatedLegs(10_001)
require(repeated.completedLegs == 10_007 && repeated.returning, "Delayed background tick preserves repeated-leg count and direction")
loop.skipRepeatedLegs(10_000)
require(loop.legName == "Lap 10011", "Delayed loop tick preserves lap count")

let reverseTrack = RouteTrack(coordinates: Array(track.coordinates.reversed()))!
var reverseJourney = RouteJourney(track: reverseTrack, speedKmh: 120)
require(near(reverseJourney.track.length, track.length), "Reverse uses the same path length")
require(near(reverseJourney.motion(paused: false).course, 270), "Reverse bearing points toward the original start")
reverseJourney.seek(0.46)
require(near(RouteSimulationMath.distance(reverseJourney.motion(paused: false).coordinate, coordinate(54)), 0), "Seeking works within the reversed leg")
reverseJourney.changeSpeed(500)
require(near(reverseJourney.motion(paused: false).speed, 500 / 3.6), "Reverse leg uses live speed metadata")
require(RouteSpeeds(defaults: defaults)[.driving] == 120, "Live leg speed must not overwrite saved mode speed")
reverseJourney.seek(1)
require(reverseJourney.motion(paused: false).speed == 0 && near(RouteSimulationMath.distance(reverseJourney.motion(paused: false).coordinate, coordinate(0)), 0), "Reverse arrival holds the exact original start")

let finishSettings = RouteFinishSettings(defaults: defaults)
require(finishSettings.action == .stay && finishSettings.destination == nil, "Default finish behavior")
finishSettings.destination = RouteFinishDestination(name: "Saved end place", address: "Test address",
    coordinate: CLLocationCoordinate2D(latitude: 39.9087, longitude: 116.3975))
finishSettings.action = .goToPlace
let restoredFinish = RouteFinishSettings(defaults: defaults)
require(restoredFinish.action == .goToPlace && restoredFinish.destination?.longitude == 116.3975, "Finish action and WGS-84 place survive relaunch")
print("PASS: six finish actions, repeat notification counts, reverse path/speed/seek, saved finish destination")

// Per-trip values and live action edits never mutate the Settings default.
finishSettings.action = .stay
var configured = RouteFinishConfiguration(defaults: finishSettings)
configured.action = .returnOnce
require(finishSettings.action == .stay, "Trip override must not change the saved default")
require(RouteFinishConfiguration(defaults: finishSettings).action == .stay, "New trip must use the default")
require(!RouteFinishConfiguration(action: .goToPlace).isValid, "Missing go-to place must not start")
for action in RouteFinishAction.allCases {
    var returning = RouteFinishState(action: .returnOnce)
    _ = returning.arrive()
    returning.changeAction(action)
    require(returning.returning && returning.completedLegs == 1, "Editing must keep current-leg orientation/history")
    let arrival = returning.arrive()
    switch action {
    case .stay, .returnOnce:
        require(arrival.effect == .hold && arrival.notification == "Staying at the start", "Hold uses the current return endpoint")
    case .goToPlace: require(arrival.effect == .goToPlace, "Return-leg jump must apply")
    case .stop: require(arrival.effect == .stop, "Return-leg stop must apply")
    case .loop: require(arrival.effect == .restart && !returning.returning && arrival.notification == nil, "Loop restarts forward without a repeated notification")
    case .backAndForth: require(arrival.effect == .reverse && !returning.returning && arrival.notification == nil, "Repeat switches the return leg forward")
    }
}
print("PASS: per-trip finish value, unchanged defaults, valid destination and six current-return-leg transitions")

let notificationSuite = "notification-tests-\(UUID().uuidString)"
let notificationDefaults = UserDefaults(suiteName: notificationSuite)!
let notificationPreferences = RouteNotificationPreferences(defaults: notificationDefaults)
require(notificationPreferences.finished && !notificationPreferences.timeSensitive, "Notification defaults must preserve current behavior")
for enabled in [false, true] {
    for sensitive in [false, true] {
        notificationPreferences.finished = enabled
        notificationPreferences.timeSensitive = sensitive
        let restored = RouteNotificationPreferences(defaults: UserDefaults(suiteName: notificationSuite)!)
        require(restored.finished == enabled && restored.timeSensitive == sensitive, "Notification choices persist independently")
        require(restored.delivery == (!enabled ? .disabled : (sensitive ? .timeSensitive : .active)), "Disabled overrides Time Sensitive")
    }
}
var mutedLoop = RouteFinishState(action: .loop)
notificationPreferences.finished = false
require(mutedLoop.arrive().notification != nil && notificationPreferences.delivery == .disabled, "Mute filters delivery, not arrival state")
notificationPreferences.finished = true
require(mutedLoop.arrive().notification == nil, "Enabling midway must not replay a repeating route's first arrival")
require(notificationPreferences.delivery != .disabled, "Existing preference readers must observe mid-route changes")
notificationDefaults.removePersistentDomain(forName: notificationSuite)
print("PASS: notification defaults, persistence, all toggle combinations and mid-trip changes")
