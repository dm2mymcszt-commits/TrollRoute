import Foundation
import CoreLocation
import Combine

struct AltitudeProfile: Codable, Equatable {
    enum Mode: String, Codable { case automatic, custom }
    var mode: Mode = .automatic
    var customMeters: Double = 0

    static func parse(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard value.range(of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil,
              let number = Double(value), number.isFinite else { return nil }
        return number
    }
}

final class AltitudeSettings: ObservableObject {
    static let shared = AltitudeSettings()
    private let defaults: UserDefaults
    @Published private(set) var profile: AltitudeProfile {
        didSet { defaults.set(try? JSONEncoder().encode(profile), forKey: "altitudeProfile") }
    }
    init(defaults: UserDefaults = SharedPreferences.defaults) {
        self.defaults = defaults
        let saved = defaults.data(forKey: "altitudeProfile").flatMap {
            try? JSONDecoder().decode(AltitudeProfile.self, from: $0)
        }
        profile = saved.flatMap { $0.customMeters.isFinite ? $0 : nil } ?? AltitudeProfile()
    }
    func setCustom(_ meters: Double) {
        guard meters.isFinite else { return }
        profile = AltitudeProfile(mode: .custom, customMeters: meters)
    }
    func reset() { profile = AltitudeProfile() }
}

enum ElevationLookup {
    static func decode(_ data: Data) -> Double? {
        decodeBatch(data, count: 1)?.first ?? nil
    }
    static func decodeBatch(_ data: Data, count: Int) -> [Double?]? {
        struct Response: Decodable { let elevation: [Double?] }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.elevation.count == count else { return nil }
        return response.elevation.map { value in value.flatMap { $0.isFinite && $0 != -9999 ? $0 : nil } }
    }
    static func fetch(_ coordinate: CLLocationCoordinate2D) async -> Double? {
        await fetchBatch([coordinate])?.first ?? nil
    }
    static func fetchBatch(_ coordinates: [CLLocationCoordinate2D]) async -> [Double?]? {
        guard (1...100).contains(coordinates.count), coordinates.allSatisfy(CLLocationCoordinate2DIsValid),
              await ElevationRequestLimiter.shared.reserve(coordinates.count), !Task.isCancelled else { return nil }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/elevation")!
        url.queryItems = [URLQueryItem(name: "latitude", value: coordinates.map { String($0.latitude) }.joined(separator: ",")),
                         URLQueryItem(name: "longitude", value: coordinates.map { String($0.longitude) }.joined(separator: ","))]
        var request = URLRequest(url: url.url!, timeoutInterval: 8)
        request.setValue("TrollRoute/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0.0") (https://github.com/dm2mymcszt-commits/TrollRoute)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return decodeBatch(data, count: coordinates.count)
    }
}

// All callers supply WGS-84 locations. Altitude is applied once, immediately
// before injection, without changing any of the caller's motion metadata.
final class AltitudeController: ObservableObject {
    @Published private(set) var currentMeters: Double?
    var isActive: Bool { currentLocation() != nil }
    private var profile: AltitudeProfile
    private let currentLocation: () -> CLLocation?
    private var cache: [(coordinate: CLLocationCoordinate2D, meters: Double)] = []
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var observation: AnyCancellable?
    private let deliver: (CLLocation) -> Void
    private let lookup: (CLLocationCoordinate2D) async -> Double?
    private let interval: TimeInterval
    private let defaults: UserDefaults
    private var nextLookup: Date
    private var routeDistance: Double?
    private var lastRouteMeters: Double?
    private var routeProfile: RouteElevationProfile?
    private let batchLookup: ([CLLocationCoordinate2D]) async -> [Double?]?
    private let routeCache = RouteElevationCache()
    private var preparedLoader: RouteElevationLoader?
    private var activeLoader: RouteElevationLoader?

    init(settings: AltitudeSettings = .shared, defaults: UserDefaults = SharedPreferences.defaults,
         interval: TimeInterval = 10,
         lookup: @escaping (CLLocationCoordinate2D) async -> Double? = ElevationLookup.fetch,
         batchLookup: @escaping ([CLLocationCoordinate2D]) async -> [Double?]? = ElevationLookup.fetchBatch,
         currentLocation: @escaping () -> CLLocation?,
         willChangeProfile: @escaping () -> Void = {},
         deliver: @escaping (CLLocation) -> Void) {
        self.profile = settings.profile
        self.defaults = defaults
        self.interval = interval
        self.lookup = lookup
        self.batchLookup = batchLookup
        self.deliver = deliver
        self.currentLocation = currentLocation
        // Persist the reservation so relaunching cannot bypass the free API limit.
        nextLookup = defaults.object(forKey: "elevationNextLookup") as? Date ?? .distantPast
        observation = settings.$profile.dropFirst().sink { [weak self] profile in
            guard let self = self else { return }
            willChangeProfile()
            self.profile = profile
            self.cancelLookup()
            self.refresh()
        }
    }

    func prepareRoute(_ plan: ElevationRoutePlan) {
        // Preparing another trip must not apply its terrain to a currently held
        // location, or cancel that location's pending terrain refinement.
        if activeLoader?.profile?.plan == plan {
            if preparedLoader !== activeLoader { preparedLoader?.cancel() }
            preparedLoader = activeLoader
        }
        if preparedLoader == nil || (preparedLoader === activeLoader && preparedLoader?.profile?.plan != plan) {
            let id = UUID()
            preparedLoader = RouteElevationLoader(id: id, cache: routeCache, lookup: batchLookup) { [weak self] profile in
                guard let self = self, self.activeLoader?.id == id else { return }
                self.routeProfile = profile
                if self.routeDistance != nil { self.refresh() }
            }
        }
        preparedLoader?.prepare(plan)
    }

    func activatePreparedRoute() {
        if activeLoader !== preparedLoader { activeLoader?.cancel() }
        activeLoader = preparedLoader
        routeProfile = activeLoader?.profile
        routeDistance = nil
        lastRouteMeters = nil
    }

    func cancelPreparedRoute() {
        if preparedLoader !== activeLoader { preparedLoader?.cancel() }
        preparedLoader = nil
    }

    func receive(routeDistance: Double? = nil) {
        if self.routeDistance != nil && routeDistance == nil { finishRoute() }
        if activeLoader == nil && routeDistance != nil { activatePreparedRoute() }
        self.routeDistance = routeDistance
        if routeDistance != nil { cancelLookup() }
        refresh(reissue: false)
    }

    func finishRoute() {
        if let coordinate = currentLocation()?.coordinate, let meters = lastRouteMeters {
            cache.append((coordinate, meters))
            if cache.count > 2048 { cache.removeFirst() }
        }
        routeDistance = nil
        lastRouteMeters = nil
        activeLoader?.cancel()
        activeLoader = nil
        routeProfile = nil
    }

    func stop() {
        cancelLookup()
        activeLoader?.cancel()
        preparedLoader?.cancel()
        activeLoader = nil
        routeProfile = nil
        routeDistance = nil
        lastRouteMeters = nil
        currentMeters = nil
    }

    /// Resolve a press-time route sample without emitting it or starting work.
    /// This also handles a pending coalesced sample whose altitude is not yet
    /// represented by LocationSession.current.
    func routeSample(_ location: CLLocation, at distance: Double) -> CLLocation {
        let meters = profile.mode == .custom ? profile.customMeters :
            (routeProfile?.meters(at: distance) ?? lastRouteMeters ?? cached(location.coordinate))
        return Self.applying(meters, to: location, accuracy: profile.mode == .custom ? 1 : 90)
    }

    /// An explicit Route Stop restores the captured height exactly. Cancel old
    /// lookups so they cannot overwrite it. A subsequent altitude-settings edit
    /// still uses the normal refresh path and applies immediately.
    func holdCaptured(_ location: CLLocation) {
        stop()
        preparedLoader = nil
        currentMeters = location.verticalAccuracy >= 0 ? location.altitude : nil
        deliver(location)
    }

    private func cancelLookup() {
        generation = UUID()
        task?.cancel()
        task = nil
    }

    private func cached(_ coordinate: CLLocationCoordinate2D) -> Double? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return cache.reversed().first {
            location.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) <= 45
        }?.meters
    }

    private func refresh(reissue: Bool = true) {
        guard let location = currentLocation() else { return }
        let terrain: Double?
        if let distance = routeDistance {
            terrain = routeProfile?.meters(at: distance) ?? lastRouteMeters ?? cached(location.coordinate)
            if let terrain = terrain { lastRouteMeters = terrain }
        } else {
            terrain = cached(location.coordinate)
        }
        let meters = profile.mode == .custom ? profile.customMeters : terrain
        currentMeters = meters
        deliver(Self.applying(meters, to: location, accuracy: profile.mode == .custom ? 1 : 90,
                              timestamp: reissue ? Date() : nil))
        guard routeDistance == nil, profile.mode == .automatic, meters == nil, task == nil else { return }
        let token = generation
        task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            while self.nextLookup > Date(), !Task.isCancelled {
                let delay = min(60, max(0, self.nextLookup.timeIntervalSinceNow))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, self.generation == token,
                  let coordinate = self.currentLocation()?.coordinate else { return }
            self.nextLookup = Date().addingTimeInterval(self.interval)
            self.defaults.set(self.nextLookup, forKey: "elevationNextLookup")
            let result = await self.lookup(coordinate)
            guard !Task.isCancelled, self.generation == token else { return }
            if let meters = result, meters.isFinite {
                self.cache.append((coordinate, meters))
                if self.cache.count > 2048 { self.cache.removeFirst() }
            } else {
                // Failed/offline lookups remain unknown; retry without hammering.
                self.nextLookup = Date().addingTimeInterval(max(60, self.interval))
                self.defaults.set(self.nextLookup, forKey: "elevationNextLookup")
            }
            self.task = nil
            // Reapply to the latest sample, never the sample that started the request.
            // A result for a place we have already left stays in the cache only.
            self.refresh()
        }
    }

    static func applying(_ meters: Double?, to location: CLLocation, accuracy: Double, timestamp: Date? = nil) -> CLLocation {
        let valid = meters?.isFinite == true
        return CLLocation(coordinate: location.coordinate, altitude: valid ? meters! : 0,
            horizontalAccuracy: location.horizontalAccuracy,
            // Core Location requires a numeric altitude; negative accuracy marks
            // that placeholder as unknown, never as a measured sea-level elevation.
            verticalAccuracy: valid ? max(1, accuracy) : -1,
            course: location.course, courseAccuracy: location.courseAccuracy,
            speed: location.speed, speedAccuracy: location.speedAccuracy, timestamp: timestamp ?? location.timestamp)
    }
}
