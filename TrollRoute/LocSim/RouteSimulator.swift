//
//  RouteSimulator.swift
//  TrollRoute
//
//  Route simulation - moves location along a real route with background support
//

import Foundation
import CoreLocation
import MapKit
import UIKit
import Combine

enum RouteSimulationMath {
    static func distance(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    static func simulationSeconds(distance: Double, speed: Double) -> TimeInterval? {
        guard distance.isFinite, distance >= 0, speed.isFinite, speed > 0 else { return nil }
        return distance / speed
    }

    static func durationText(_ seconds: TimeInterval?) -> String {
        guard let seconds = seconds, seconds.isFinite, seconds >= 0,
              seconds < Double(Int.max) else { return "Unavailable" }
        let rounded = Int(ceil(seconds))
        if rounded < 60 { return "\(rounded)s" }
        let minutes = rounded / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m \(rounded % 60)s"
    }

    // Every alternative uses the same simulation speed, so shortest is fastest.
    static func rankedIndices(distances: [Double]) -> [Int] {
        return distances.indices.sorted { lhs, rhs in
            let lhsDistance = distances[lhs].isFinite && distances[lhs] > 0 ? distances[lhs] : .infinity
            let rhsDistance = distances[rhs].isFinite && distances[rhs] > 0 ? distances[rhs] : .infinity
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs < rhs
        }
    }


}

// Distances and bearings are measured in WGS-84. The map conversion happens
// only at the boundary, so motion metadata describes the injected coordinates.
struct RouteTrack {
    let coordinates: [CLLocationCoordinate2D]
    let cumulative: [Double]
    var length: Double { cumulative.last ?? 0 }

    init?(coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count >= 2, coordinates.allSatisfy(CLLocationCoordinate2DIsValid) else { return nil }
        var points = [coordinates[0]]
        var distances = [0.0]
        for point in coordinates.dropFirst() {
            let distance = RouteSimulationMath.distance(points.last!, point)
            if distance > 0.001 {
                points.append(point)
                distances.append(distances.last! + distance)
            }
        }
        guard points.count >= 2 else { return nil }
        self.coordinates = points
        cumulative = distances
    }

    func position(at distance: Double) -> (coordinate: CLLocationCoordinate2D, course: Double) {
        let distance = min(length, max(0, distance.isFinite ? distance : 0))
        var low = 1, high = cumulative.count - 1
        while low < high {
            let middle = (low + high) / 2
            if cumulative[middle] <= distance { low = middle + 1 } else { high = middle }
        }
        let from = coordinates[low - 1], to = coordinates[low]
        let fraction = (distance - cumulative[low - 1]) / (cumulative[low] - cumulative[low - 1])
        let delta = (to.longitude - from.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        let longitude = (from.longitude + delta * fraction + 540).truncatingRemainder(dividingBy: 360) - 180
        let coordinate = distance == length ? coordinates.last! : CLLocationCoordinate2D(
            latitude: from.latitude + (to.latitude - from.latitude) * fraction, longitude: longitude)
        let lat1 = coordinate.latitude * .pi / 180, lat2 = to.latitude * .pi / 180
        let dlon = (to.longitude - coordinate.longitude) * .pi / 180
        // At the exact destination retain the final segment's bearing.
        let origin = distance == length ? from : coordinate
        let originLat = distance == length ? from.latitude * .pi / 180 : lat1
        let bearingLon = distance == length ? (to.longitude - origin.longitude) * .pi / 180 : dlon
        let course = (atan2(sin(bearingLon) * cos(lat2), cos(originLat) * sin(lat2)
            - sin(originLat) * cos(lat2) * cos(bearingLon)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return (coordinate, course)
    }
}

struct RouteJourney {
    let track: RouteTrack
    private(set) var distance = 0.0
    private(set) var elapsed = 0.0
    private(set) var speedKmh: Double
    var progress: Double { distance / track.length }
    var remainingDistance: Double { max(0, track.length - distance) }
    var remainingSeconds: Double { remainingDistance / (speedKmh / 3.6) }
    var isFinished: Bool { distance >= track.length }

    init(track: RouteTrack, speedKmh: Double) {
        self.track = track
        self.speedKmh = speedKmh.isFinite ? min(500, max(1, speedKmh)) : 50
    }
    mutating func advance(seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        let remaining = remainingSeconds
        let used = min(seconds, remaining)
        elapsed += used
        distance = min(track.length, distance + speedKmh / 3.6 * used)
        if used == remaining { distance = track.length }
    }
    mutating func seek(_ fraction: Double) {
        guard fraction.isFinite else { return }
        distance = min(1, max(0, fraction)) * track.length
    }
    mutating func changeSpeed(_ kmh: Double) {
        guard kmh.isFinite else { return }
        speedKmh = min(500, max(1, kmh))
    }
    func motion(paused: Bool) -> (coordinate: CLLocationCoordinate2D, course: Double, speed: Double) {
        let point = track.position(at: distance)
        return (point.coordinate, point.course, paused || isFinished ? 0 : speedKmh / 3.6)
    }
}

enum TravelMode: String, CaseIterable {
    case walking = "Walking"
    case cycling = "Cycling"
    case driving = "Driving"
    
    var defaultSpeedKmh: Double {
        switch self {
        case .walking: return 5
        case .cycling: return 20
        case .driving: return 50
        }
    }
    
    var icon: String {
        switch self {
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .driving: return "car.fill"
        }
    }
    
    var appleTransportType: MKDirectionsTransportType? {
        switch self {
        case .walking: return .walking
        case .cycling: return nil // MapKit has no bicycle directions API.
        case .driving: return .automobile
        }
    }
}

struct RouteSpeeds {
    private var values: [TravelMode: Double] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = SharedPreferences.defaults) {
        self.defaults = defaults
        for mode in TravelMode.allCases {
            let saved = defaults.double(forKey: Self.key(mode))
            values[mode] = saved.isFinite && (1...500).contains(saved) ? saved : mode.defaultSpeedKmh
        }
    }

    subscript(mode: TravelMode) -> Double { values[mode] ?? mode.defaultSpeedKmh }
    private static func key(_ mode: TravelMode) -> String { "routeSpeedKmh." + mode.rawValue.lowercased() }
    mutating func set(_ kmh: Double, for mode: TravelMode) {
        guard kmh.isFinite else { return }
        let speed = min(500, max(1, kmh))
        values[mode] = speed
        defaults.set(speed, forKey: Self.key(mode))
    }
}

// A provider-independent route keeps mode selection and future travel modes
// separate from Apple's read-only MKRoute type.
struct RoutePath {
    let polyline: MKPolyline
    let distance: Double
    let expectedTravelTime: TimeInterval
    let name: String
    let trafficLabel: String

    init(_ route: MKRoute, mode: TravelMode) {
        polyline = route.polyline
        distance = route.distance
        expectedTravelTime = route.expectedTravelTime
        name = route.name
        trafficLabel = mode == .driving ? "Real traffic" : "Typical travel"
    }

    init(polyline: MKPolyline, distance: Double, expectedTravelTime: TimeInterval,
         name: String, trafficLabel: String = "Typical travel") {
        self.polyline = polyline
        self.distance = distance
        self.expectedTravelTime = expectedTravelTime
        self.name = name
        self.trafficLabel = trafficLabel
    }
}

struct RouteModeCache {
    private(set) var routes: [TravelMode: [RouteOption]] = [:]
    private(set) var selections: [TravelMode: Int] = [:]
    mutating func store(_ paths: [RoutePath], for mode: TravelMode) {
        let valid = paths.filter { $0.polyline.pointCount >= 2 && $0.distance.isFinite && $0.distance > 0 }
        routes[mode] = RouteSimulationMath.rankedIndices(distances: valid.map(\.distance))
            .enumerated().map { RouteOption(route: valid[$0.element], index: $0.offset) }
        selections[mode] = 0
    }
    mutating func select(_ index: Int, for mode: TravelMode) {
        guard routes[mode]?.indices.contains(index) == true else { return }
        selections[mode] = index
    }
    func duration(for mode: TravelMode, kmh: Double) -> String? {
        routes[mode]?.first?.simulationTimeText(speedKmh: kmh)
    }
}

enum BicycleRouteError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Cycling directions are unavailable. Please try calculating again." }
}

actor BicycleDirections {
    static let shared = BicycleDirections()
    private var nextRequest = Date.distantPast
    // A single reservation queue keeps requests over one second apart, even
    // when an earlier route was cancelled. No requests happen on tab/speed changes.
    func routes(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> [RoutePath] {
        let delay = max(0, nextRequest.timeIntervalSinceNow)
        nextRequest = Date().addingTimeInterval(delay + 1.1)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        let start = CoordTransform.gcj02ToWgs84(start)
        let end = CoordTransform.gcj02ToWgs84(end)
        let pair = "\(start.longitude),\(start.latitude);\(end.longitude),\(end.latitude)"
        let url = URL(string: "https://routing.openstreetmap.de/routed-bike/route/v1/bike/\(pair)?alternatives=true&overview=full&geometries=geojson&steps=false")!
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("TrollRoute/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0.0") (https://github.com/dm2mymcszt-commits/TrollRoute)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BicycleRouteError.unavailable }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [RoutePath] {
        struct Response: Decodable {
            struct Route: Decodable {
                struct Geometry: Decodable { let coordinates: [[Double]] }
                struct Leg: Decodable { let summary: String? }
                let geometry: Geometry
                let distance: Double
                let duration: Double
                let legs: [Leg]
            }
            let code: String
            let routes: [Route]?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.code == "Ok" else { throw BicycleRouteError.unavailable }
        let routes = (response.routes ?? []).compactMap { route -> RoutePath? in
            let coords = route.geometry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count == 2 else { return nil }
                let coord = CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                return CLLocationCoordinate2DIsValid(coord) ? CoordTransform.wgs84ToGcj02(coord) : nil
            }
            guard coords.count == route.geometry.coordinates.count, coords.count >= 2,
                  route.distance.isFinite, route.distance > 0 else { return nil }
            return RoutePath(polyline: MKPolyline(coordinates: coords, count: coords.count),
                             distance: route.distance, expectedTravelTime: route.duration,
                             name: route.legs.compactMap(\.summary).filter { !$0.isEmpty }.joined(separator: ", "))
        }
        guard !routes.isEmpty else { throw BicycleRouteError.unavailable }
        return routes
    }
}

class RouteOption: Identifiable, ObservableObject {
    let id = UUID()
    let route: RoutePath
    let index: Int

    var isFastest: Bool {
        index == 0 && route.distance.isFinite && route.distance > 0
    }
    
    var name: String {
        if isFastest { return "Fastest Route" }
        if index == 0 { return "Route 1" }
        return "Alternative \(index)"
    }
    
    var distanceText: String {
        if route.distance >= 1000 {
            return String(format: "%.1f km", route.distance / 1000)
        }
        return String(format: "%.0f m", route.distance)
    }
    
    var trafficTimeText: String {
        guard route.expectedTravelTime.isFinite, route.expectedTravelTime > 0 else { return "ETA unavailable" }
        let minutes = max(1, Int(ceil(route.expectedTravelTime / 60)))
        if minutes >= 60 {
            let hours = minutes / 60
            let rem = minutes % 60
            return "\(hours)h \(rem)m"
        }
        return "\(minutes) min"
    }

    func simulationTimeText(speedKmh: Double) -> String {
        RouteSimulationMath.durationText(RouteSimulationMath.simulationSeconds(
            distance: route.distance, speed: speedKmh / 3.6))
    }
    
    init(route: RoutePath, index: Int) {
        self.route = route
        self.index = index
    }
}

class RouteSimulator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isSimulating: Bool = false
    @Published var isPaused: Bool = false
    @Published var routePolyline: MKPolyline? = nil
    let locationSession: LocationSession
    var currentPosition: CLLocationCoordinate2D? {
        // Rendering follows geometry immediately, independently of injection slots.
        if isSimulating, let journey = journey {
            return CoordTransform.wgs84ToGcj02(journey.motion(paused: isPaused).coordinate)
        }
        return locationSession.current.map { CoordTransform.wgs84ToGcj02($0.coordinate) }
    }
    @Published var progress: Double = 0.0
    @Published var isCalculatingRoute: Bool = false
    @Published var travelMode: TravelMode = .driving
    @Published private var finishState = RouteFinishState(action: .stay)
    @Published private(set) var startError: String?
    @Published private(set) var finishConfiguration: RouteFinishConfiguration
    @Published private(set) var stopRequest: RouteStopRequest?
    private var tripID: UUID?
    private let stopDefaults: UserDefaults
    private let finishDefaults: RouteFinishSettings
    private let now: () -> TimeInterval
    private let notifyCompletion: (String) -> Void

    func configureFinish(_ configuration: RouteFinishConfiguration) {
        guard configuration.isValid else { return }
        finishConfiguration = configuration
        if isSimulating { finishState.changeAction(configuration.action) }
    }
    var legName: String { finishState.legName }
    var displayedPolylines: [MKPolyline] { isSimulating ? routePolyline.map { [$0] } ?? [] : allRoutePolylines }
    
    @Published var availableRoutes: [RouteOption] = []
    @Published var allRoutePolylines: [MKPolyline] = []
    @Published var selectedRouteIndex: Int = 0
    @Published var routeStart: CLLocationCoordinate2D? = nil
    @Published var routeEnd: CLLocationCoordinate2D? = nil
    
    private var track: RouteTrack?
    @Published private var journey: RouteJourney?
    @Published private(set) var previewPosition: CLLocationCoordinate2D?
    @Published private var seekFraction: Double?
    private var isSeeking: Bool { seekFraction != nil }
    private var lastTick: TimeInterval?
    var elapsedTime: String { RouteSimulationMath.durationText(journey?.elapsed ?? 0) }
    private var remainingMeters: Double {
        guard let journey = journey else { return 0 }
        return (1 - (seekFraction ?? journey.progress)) * journey.track.length
    }
    var remainingTime: String { RouteSimulationMath.durationText(remainingMeters / (currentSpeedKmh / 3.6)) }
    var remainingDistance: String {
        let meters = remainingMeters
        return meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(ceil(meters))) m"
    }
    private var timer: Timer? = nil
    @Published private var speeds = RouteSpeeds()
    @Published private var modeCache = RouteModeCache()
    @Published private(set) var modeErrors: [TravelMode: String] = [:]
    func speedKmh(for mode: TravelMode) -> Double { speeds[mode] }
    var currentSpeedKmh: Double { isSimulating ? (journey?.speedKmh ?? speeds[travelMode]) : speeds[travelMode] }
    func modeDuration(_ mode: TravelMode) -> String? { modeCache.duration(for: mode, kmh: speeds[mode]) }
    var simulatedRouteETAs: [String] {
        if isSimulating, let journey = journey {
            return [RouteSimulationMath.durationText(journey.track.length / (currentSpeedKmh / 3.6))]
        }
        return availableRoutes.map { $0.simulationTimeText(speedKmh: currentSpeedKmh) }
    }
    private let updateInterval: TimeInterval = 0.25
    private var pendingDirections: [TravelMode: MKDirections] = [:]
    private var bicycleTask: Task<Void, Never>?
    private var calculationID = UUID()
    
    // Background handling
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let locationManager = CLLocationManager()
    
    init(locationSession: LocationSession = LocSimManager.session,
         finishDefaults: RouteFinishSettings = .shared,
         stopDefaults: UserDefaults = SharedPreferences.defaults,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         notifyCompletion: @escaping (String) -> Void = { RouteNotifications.shared.complete($0) }) {
        self.locationSession = locationSession
        self.finishDefaults = finishDefaults
        self.stopDefaults = stopDefaults
        finishConfiguration = RouteFinishConfiguration(defaults: finishDefaults)
        self.now = now
        self.notifyCompletion = notifyCompletion
        super.init()
        locationSession.onOwnershipLost = { [weak self] in
            guard let self = self, self.isSimulating else { return }
            self.endPlayback()
        }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }
    
    func calculateRoutes(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, mode: TravelMode, completion: @escaping (Bool, String?) -> Void) {
        guard !isSimulating else {
            completion(false, "Stop the current simulation before calculating another route.")
            return
        }
        clearCalculatedRoutes()
        guard CLLocationCoordinate2DIsValid(start), CLLocationCoordinate2DIsValid(end) else {
            completion(false, "Choose valid endpoints.")
            return
        }
        isCalculatingRoute = true
        travelMode = mode
        routeStart = start
        routeEnd = end
        let requestID = calculationID
        var remaining = TravelMode.allCases.count
        // All results belong to the same endpoint snapshot. Cancellation discards
        // the entire generation, including a late bicycle response after swapping.
        let receive: (TravelMode, [RoutePath], String?) -> Void = { [weak self] mode, routes, error in
            guard let self = self, self.calculationID == requestID else { return }
            self.pendingDirections[mode] = nil
            self.modeCache.store(routes, for: mode)
            if routes.isEmpty { self.modeErrors[mode] = error ?? "No route found for this mode." }
            remaining -= 1
            guard remaining == 0 else { return }
            self.bicycleTask = nil
            self.isCalculatingRoute = false
            self.selectMode(self.travelMode)
            // Keep successful modes available even if another mode has no route.
            completion(!self.availableRoutes.isEmpty, self.modeErrors[self.travelMode])
        }
        for mode in TravelMode.allCases {
            if let transport = mode.appleTransportType {
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
                request.transportType = transport
                request.requestsAlternateRoutes = true
                request.departureDate = Date()
                let directions = MKDirections(request: request)
                pendingDirections[mode] = directions
                directions.calculate { response, error in
                    DispatchQueue.main.async {
                        receive(mode, (response?.routes ?? []).map { RoutePath($0, mode: mode) }, error?.localizedDescription)
                    }
                }
            } else {
                bicycleTask = Task { @MainActor in
                    do { receive(mode, try await BicycleDirections.shared.routes(from: start, to: end), nil) }
                    catch { receive(mode, [], error.localizedDescription) }
                }
            }
        }
    }

    func selectMode(_ mode: TravelMode) {
        guard !isSimulating else { return }
        locationSession.altitudeController.cancelPreparedRoute()
        travelMode = mode
        availableRoutes = modeCache.routes[mode] ?? []
        allRoutePolylines = availableRoutes.map { $0.route.polyline }
        routePolyline = nil
        track = nil
        journey = nil
        selectedRouteIndex = modeCache.selections[mode] ?? 0
        selectRoute(at: selectedRouteIndex)
    }

    func selectRoute(at index: Int) {
        guard !isSimulating, availableRoutes.indices.contains(index) else { return }
        selectedRouteIndex = index
        modeCache.select(index, for: travelMode)
        let route = availableRoutes[index].route
        
        let pointCount = route.polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        
        track = RouteTrack(coordinates: coords.map(CoordTransform.gcj02ToWgs84))
        prepareElevation()
        journey = nil
        routePolyline = route.polyline
        
    }

    func updateSpeedKmh(_ kmh: Double, for mode: TravelMode) {
        guard !isSimulating else { return }
        speeds.set(kmh, for: mode)
        if mode == travelMode { selectRoute(at: selectedRouteIndex) }
    }

    func clearCalculatedRoutes() {
        guard !isSimulating else { return }
        finishConfiguration = RouteFinishConfiguration(defaults: finishDefaults)
        locationSession.altitudeController.cancelPreparedRoute()
        calculationID = UUID()
        pendingDirections.values.forEach { $0.cancel() }
        pendingDirections = [:]
        bicycleTask?.cancel()
        bicycleTask = nil
        modeCache = RouteModeCache()
        modeErrors = [:]
        isCalculatingRoute = false
        availableRoutes = []
        allRoutePolylines = []
        routePolyline = nil
        track = nil
        journey = nil
        previewPosition = nil
        seekFraction = nil
        routeStart = nil
        routeEnd = nil
        selectedRouteIndex = 0
        progress = 0
    }
    
    func startSimulation() {
        guard !isSimulating, let track = track else { return }
        startError = nil
        guard finishConfiguration.isValid else {
            startError = "Choose where this route should finish before starting."
            return
        }
        guard locationSession.beginRoute(prepare: { self.prepareElevation() }) else {
            startError = locationSession.error ?? "Couldn't start location simulation."
            return
        }
        tripID = UUID()
        stopRequest = nil
        finishState = RouteFinishState(action: finishConfiguration.action)
        timer?.invalidate()
        journey = RouteJourney(track: track, speedKmh: speeds[travelMode])
        isSimulating = true
        isPaused = false
        progress = 0
        previewPosition = nil
        seekFraction = nil
        updateBackgroundLocationAccess()
        startBackgroundTask()
        updateLocation()
        if isSimulating { startTimer() }
    }

    private func startTimer() {
        timer?.invalidate()
        lastTick = now()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.advanceRoute()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func togglePause() {
        guard isSimulating else { return }
        if isPaused {
            isPaused = false
            startBackgroundTask()
            startTimer()
        } else {
            advanceRoute()
            guard isSimulating else { return }
            isPaused = true
            timer?.invalidate()
            timer = nil
            lastTick = nil
        }
        updateLocation(reason: .stateChange)
    }

    func updateLiveSpeed(_ kmh: Double) {
        guard isSimulating, kmh.isFinite else { return }
        advanceRoute() // Account for time at the previous speed first.
        guard isSimulating else { return }
        journey?.changeSpeed(kmh)
        updateLocation()
    }

    func previewSeek(_ fraction: Double) {
        guard isSimulating, fraction.isFinite else { return }
        let beginning = !isSeeking
        if beginning {
            advanceRoute()
            guard isSimulating else { return }
        }
        guard let journey = journey else { return }
        seekFraction = min(1, max(0, fraction))
        let point = journey.track.position(at: min(1, max(0, fraction)) * journey.track.length)
        previewPosition = CoordTransform.wgs84ToGcj02(point.coordinate)
    }

    func cancelSeek() {
        guard isSeeking else { return }
        previewPosition = nil
        seekFraction = nil
    }

    func seek(to fraction: Double) {
        guard isSimulating, fraction.isFinite else { return }
        // The preview never paused playback. Account for elapsed motion before
        // committing the single instantaneous jump when the finger is released.
        advanceRoute()
        guard isSimulating else { previewPosition = nil; return }
        journey?.seek(fraction)
        previewPosition = nil
        seekFraction = nil
        lastTick = isPaused ? nil : now()
        updateLocation(reason: .jump)
        if journey?.isFinished == true { finishRoute() }
    }

    func requestRouteStop() {
        guard isSimulating, stopRequest == nil else { return }
        advanceRoute()
        guard isSimulating, let tripID = tripID, let journey = journey, let track = track else { return }
        let motion = journey.motion(paused: true)
        let distance = finishState.returning ? track.length - journey.distance : journey.distance
        let current = locationSession.altitudeController.routeSample(RouteLocationSample.make(
            coordinate: motion.coordinate, course: motion.course, speed: 0, timestamp: Date()), at: distance)
        let start = track.position(at: 0)
        let startSample = locationSession.altitudeController.routeSample(RouteLocationSample.make(
            coordinate: start.coordinate, course: start.course, speed: 0, timestamp: Date()), at: 0)
        stopRequest = RouteStopRequest(tripID: tripID, previous: locationSession.snapshot.beforeRoute,
            current: SessionLocation(current), start: SessionLocation(startSample),
            preferred: RouteStopAction.savedDefault(in: stopDefaults))
    }

    func cancelRouteStop(_ id: UUID) {
        guard stopRequest?.id == id else { return }
        stopRequest = nil
    }

    func confirmRouteStop(_ id: UUID, action: RouteStopAction, place: RouteFinishDestination? = nil) {
        if locationSession.refreshShared() { return }
        guard isSimulating, let request = stopRequest, request.id == id,
              request.tripID == tripID, request.choices.contains(action) else { return }
        if action == .specific {
            guard let place = place, CLLocationCoordinate2DIsValid(place.coordinate) else { return }
        }
        if action == .real { stopSimulation(newIntent: false); return }
        endPlayback()
        switch action {
        case .previous:
            if let previous = request.previous { locationSession.holdCaptured(previous) }
        case .current: locationSession.holdCaptured(request.current)
        case .start: locationSession.holdCaptured(request.start)
        case .specific:
            if let place = place {
                locationSession.receive(RouteLocationSample.make(coordinate: place.coordinate,
                    course: 0, speed: 0, timestamp: Date()), kind: .stationary, reason: .jump)
            }
        case .real: break // Handled before ending playback.
        }
    }

    /// Only Main Stop and an explicitly chosen real-location outcome use this.
    func stopSimulation(newIntent: Bool = true) {
        endPlayback()
        locationSession.stop(newIntent: newIntent)
    }

    private func endPlayback() {
        timer?.invalidate()
        timer = nil
        lastTick = nil
        isSimulating = false
        isPaused = false
        tripID = nil
        stopRequest = nil
        clearCalculatedRoutes()
        locationManager.stopUpdatingLocation()
        endBackgroundTask()
    }

    func advanceRoute() {
        guard isSimulating, !isPaused else { return }
        let tickTime = now()
        var seconds = lastTick.map { max(0, tickTime - $0) } ?? 0
        lastTick = tickTime
        while isSimulating {
            let remaining = journey?.remainingSeconds ?? 0
            journey?.advance(seconds: seconds)
            updateLocation()
            guard journey?.isFinished == true else { break }
            seconds = max(0, seconds - remaining)
            finishRoute()
            guard isSimulating, !isPaused, seconds > 0 else { break }
            // A delayed background tick may span many very short repeated legs.
            // Skip their elapsed time arithmetically without a notification flood.
            if finishState.action == .loop || finishState.action == .backAndForth,
               let journey = journey, journey.remainingSeconds > 0 {
                let count = Int(min(Double(Int.max / 2), floor(seconds / journey.remainingSeconds)))
                if count > 0 {
                    finishState.skipRepeatedLegs(count)
                    seconds -= Double(count) * journey.remainingSeconds
                    let next = finishState.returning ? RouteTrack(coordinates: Array(track!.coordinates.reversed()))! : track!
                    beginLeg(next, speedKmh: journey.speedKmh)
                }
            }
        }
    }

    private func finishRoute() {
        let transition = finishState.arrive()
        if let message = transition.notification { notifyCompletion(message) }
        switch transition.effect {
        case .restart:
            if let track = track { beginLeg(track, speedKmh: currentSpeedKmh) }
            return
        case .reverse:
            if let journey = journey, let reversed = RouteTrack(coordinates: Array(journey.track.coordinates.reversed())) {
                beginLeg(reversed, speedKmh: journey.speedKmh)
            }
            return
        case .stop:
            stopSimulation(newIntent: false)
            return
        case .goToPlace:
            if let destination = finishConfiguration.destination {
                locationSession.receive(RouteLocationSample.make(coordinate: destination.coordinate,
                    course: 0, speed: 0, timestamp: Date()), kind: .stationary)
            }
        case .hold: break
        }
        locationSession.finishHolding()
        tripID = nil
        stopRequest = nil
        // The final sample has already published exact destination and zero speed.
        timer?.invalidate()
        timer = nil
        lastTick = nil
        isSimulating = false
        isPaused = false
        previewPosition = nil
        seekFraction = nil
        progress = 1
        endBackgroundTask()
        locationManager.stopUpdatingLocation()
    }

    private func beginLeg(_ track: RouteTrack, speedKmh: Double) {
        let previous = locationSession.inputSample?.coordinate
        journey = RouteJourney(track: track, speedKmh: speedKmh)
        let coords = track.coordinates.map(CoordTransform.wgs84ToGcj02)
        routePolyline = MKPolyline(coordinates: coords, count: coords.count)
        // A held scrub always previews the current leg, including when a loop
        // or reverse transition occurs before the finger is released.
        if let fraction = seekFraction {
            previewPosition = CoordTransform.wgs84ToGcj02(track.position(at: fraction * track.length).coordinate)
        }
        // Keep the same timer, background task and location updates across legs.
        let start = track.coordinates[0]
        let jumped = previous.map { $0.latitude != start.latitude || $0.longitude != start.longitude } ?? true
        updateLocation(reason: jumped ? .jump : .stateChange)
    }

    private func updateBackgroundLocationAccess() {
        guard isSimulating else { return }
        let status = LocationAccessStatus(registration: nil,
            coreAuthorization: locationManager.authorizationStatus,
            coreAccuracy: locationManager.accuracyAuthorization,
            servicesEnabled: CLLocationManager.locationServicesEnabled())
        let foreground = UIApplication.shared.applicationState != .background
        if status.authorization == .notDetermined && status.servicesEnabled && foreground {
            locationManager.requestWhenInUseAuthorization()
        }
        if status.canStartUpdates(inForeground: foreground) {
            locationManager.startUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Start the keepalive after a permission response. Pause/Resume retains
        // this stream; only terminal finish/Stop ends it. Never prompt from background.
        updateBackgroundLocationAccess()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location delivery also advances time if iOS delayed a timer while locked.
        // Ignore the immediate echo of our own injected sample.
        guard let lastTick = lastTick, now() - lastTick >= updateInterval else { return }
        advanceRoute()
    }

    private func updateLocation(reason: LocationInjectionReason = .continuous) {
        guard let journey = journey else { return }
        let motion = journey.motion(paused: isPaused)
        progress = journey.progress
        let location = RouteLocationSample.make(coordinate: motion.coordinate,
            course: motion.course, speed: motion.speed, timestamp: Date())
        let distance = finishState.returning ? (track?.length ?? journey.track.length) - journey.distance : journey.distance
        locationSession.receive(location, kind: .route, reason: reason, routeDistance: distance)
    }

    private func prepareElevation() {
        guard let track = track else { return }
        locationSession.altitudeController.prepareRoute(ElevationRoutePlan(length: track.length,
            position: { track.position(at: $0).coordinate }))
    }

    // MARK: - Background Task Management
    private func startBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "RouteSimulation") { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
