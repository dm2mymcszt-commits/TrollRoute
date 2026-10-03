import Foundation
import CoreLocation

struct FlightAirport: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let city: String
    let country: String
    let codes: [String]
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var code: String { codes.first ?? id }
    var title: String { "\(name) (\(code))" }
    func matches(_ query: String) -> Bool {
        ([name, city, country, id] + codes).joined(separator: " ")
            .range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
    func withElevation(_ meters: Double) -> FlightAirport {
        FlightAirport(id: id, name: name, city: city, country: country, codes: codes,
            latitude: latitude, longitude: longitude, elevation: meters)
    }
}

struct AirportCatalog {
    let airports: [FlightAirport]
    static let bundled: AirportCatalog = {
        guard let url = Bundle.main.url(forResource: "Airports", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? AirportCatalog(data: data) else {
            return AirportCatalog(airports: [])
        }
        return catalog
    }()
    init(airports: [FlightAirport]) { self.airports = airports }
    init(data: Data) throws {
        let decoded = try JSONDecoder().decode([FlightAirport].self, from: data)
        airports = decoded.filter {
            CLLocationCoordinate2DIsValid($0.coordinate) && ($0.elevation?.isFinite ?? true)
        }.sorted { $0.id < $1.id }
    }
    func nearest(to point: CLLocationCoordinate2D) -> FlightAirport? {
        guard CLLocationCoordinate2DIsValid(point) else { return nil }
        return airports.min {
            let a = GreatCircle.angularDistance(point, $0.coordinate)
            let b = GreatCircle.angularDistance(point, $1.coordinate)
            return abs(a - b) < 1e-12 ? $0.id < $1.id : a < b
        }
    }
    func search(_ query: String) -> [FlightAirport] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? airports : airports.filter { $0.matches(query) }
    }
}

/// Spherical geometry, independent of Mercator and longitude wrapping.
struct GreatCircle {
    static let radius = 6_371_008.8
    private struct Vector {
        let x: Double, y: Double, z: Double
        static func + (a: Vector, b: Vector) -> Vector { .init(x: a.x+b.x, y: a.y+b.y, z: a.z+b.z) }
        static func * (a: Vector, b: Double) -> Vector { .init(x: a.x*b, y: a.y*b, z: a.z*b) }
        func dot(_ b: Vector) -> Double { x*b.x + y*b.y + z*b.z }
        func cross(_ b: Vector) -> Vector { .init(x: y*b.z-z*b.y, y: z*b.x-x*b.z, z: x*b.y-y*b.x) }
        var norm: Double { sqrt(dot(self)) }
        var unit: Vector { self * (1 / norm) }
        init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
        init(_ p: CLLocationCoordinate2D) {
            let lat = p.latitude * .pi / 180, lon = p.longitude * .pi / 180
            self.init(x: cos(lat)*cos(lon), y: cos(lat)*sin(lon), z: sin(lat))
        }
    }
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let angle: Double
    private let origin: Vector
    private let tangent: Vector
    var length: Double { angle * Self.radius }
    static func angularDistance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let x = Vector(a), y = Vector(b)
        return atan2(x.cross(y).norm, x.dot(y))
    }
    init?(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(start), CLLocationCoordinate2DIsValid(end) else { return nil }
        let a = Vector(start), b = Vector(end)
        let cross = a.cross(b)
        let angle = atan2(cross.norm, a.dot(b))
        guard angle * Self.radius > 1 else { return nil }
        self.start = start; self.end = end; self.angle = angle; origin = a
        if cross.norm > 1e-12 {
            tangent = cross.unit.cross(a).unit
        } else {
            // Antipodal points have infinitely many shortest arcs. Choose a
            // deterministic plane with a well-conditioned perpendicular axis.
            let axis = abs(a.z) < 0.9 ? Vector(x: 0, y: 0, z: 1) : Vector(x: 1, y: 0, z: 0)
            tangent = (axis + a * (-axis.dot(a))).unit
        }
    }
    func position(_ fraction: Double) -> (coordinate: CLLocationCoordinate2D, course: Double) {
        let f = min(1, max(0, fraction.isFinite ? fraction : 0)), t = f * angle
        let p = origin * cos(t) + tangent * sin(t)
        let v = origin * (-sin(t)) + tangent * cos(t)
        let coordinate = f == 0 ? start : f == 1 ? end : CLLocationCoordinate2D(
            latitude: atan2(p.z, hypot(p.x, p.y)) * 180 / .pi,
            longitude: atan2(p.y, p.x) * 180 / .pi)
        let lat = coordinate.latitude * .pi / 180, lon = coordinate.longitude * .pi / 180
        let north = Vector(x: -sin(lat)*cos(lon), y: -sin(lat)*sin(lon), z: cos(lat))
        let east = Vector(x: -sin(lon), y: cos(lon), z: 0)
        let course = (atan2(v.dot(east), v.dot(north)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return (coordinate, course)
    }
    var coordinates: [CLLocationCoordinate2D] {
        let steps = max(2, Int(ceil(length / 10_000)))
        return (0...steps).map { position(Double($0) / Double(steps)).coordinate }
    }
}

enum FlightError: LocalizedError {
    case airportsUnavailable, sameAirport, elevationUnavailable, profileUnavailable
    var errorDescription: String? {
        switch self {
        case .airportsUnavailable: return "The bundled airport list could not be loaded."
        case .sameAirport: return "Choose two different airports for a flight."
        case .elevationUnavailable: return "Airport elevation is unavailable. Try again or choose another airport."
        case .profileUnavailable: return "These airports are too close for a realistic flight between their elevations. Choose another airport."
        }
    }
}

struct FlightPlan {
    let departure: FlightAirport
    let arrival: FlightAirport
    let path: GreatCircle
    let profile: FlightProfile
    init(departure: FlightAirport, arrival: FlightAirport) throws {
        guard departure.id != arrival.id, let path = GreatCircle(from: departure.coordinate, to: arrival.coordinate) else {
            throw FlightError.sameAirport
        }
        guard let a = departure.elevation, let b = arrival.elevation else { throw FlightError.elevationUnavailable }
        guard let profile = FlightProfile(length: path.length, departureElevation: a, arrivalElevation: b) else {
            throw FlightError.profileUnavailable
        }
        self.departure = departure; self.arrival = arrival; self.path = path; self.profile = profile
    }
    func reversed() throws -> FlightPlan { try FlightPlan(departure: arrival, arrival: departure) }
}

actor AirportElevationResolver {
    static let shared = AirportElevationResolver()
    private struct Entry: Codable {
        let meters: Double
        let date: Date
        let latitude: Double
        let longitude: Double
        let source: String
    }
    private let defaults: UserDefaults
    private var entries: [String: Entry]
    private var failedUntil: [String: Date] = [:]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: "flightAirportElevations.v1").flatMap {
            try? JSONDecoder().decode([String: Entry].self, from: $0)
        } ?? [:]
    }
    func resolve(_ airport: FlightAirport,
                 lookup: (CLLocationCoordinate2D) async -> Double?) async throws -> FlightAirport {
        if let elevation = airport.elevation, elevation.isFinite { return airport }
        if let saved = entries[airport.id], saved.meters.isFinite,
           saved.latitude == airport.latitude, saved.longitude == airport.longitude,
           Date().timeIntervalSince(saved.date) < 30 * 86400 {
            return airport.withElevation(saved.meters)
        }
        guard (failedUntil[airport.id] ?? .distantPast) <= Date() else { throw FlightError.elevationUnavailable }
        guard let height = await lookup(airport.coordinate), height.isFinite else {
            failedUntil[airport.id] = Date().addingTimeInterval(60)
            throw FlightError.elevationUnavailable
        }
        entries[airport.id] = Entry(meters: height, date: Date(), latitude: airport.latitude,
            longitude: airport.longitude, source: "Open-Meteo")
        if entries.count > 256, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key { entries[oldest] = nil }
        defaults.set(try? JSONEncoder().encode(entries), forKey: "flightAirportElevations.v1")
        return airport.withElevation(height)
    }
}

/// Distance-based altitude never changes when the cruise setting changes.
/// Speed envelope sqrt(2u-u*u) has an analytic time integral, including its
/// stationary endpoints. Thus seeking, long ticks and ETA need no time steps.
struct FlightProfile {
    let length: Double
    let departureElevation: Double
    let arrivalElevation: Double
    let cruiseAltitude: Double
    let climbLength: Double
    let descentLength: Double
    let maximumSpeed: Double
    private var climbClock: Double { climbLength * .pi / 2 }
    private var cruiseLength: Double { length - climbLength - descentLength }
    var totalClock: Double { climbClock + cruiseLength + descentLength * .pi / 2 }
    init?(length: Double, departureElevation: Double, arrivalElevation: Double) {
        guard [length, departureElevation, arrivalElevation].allSatisfy(\.isFinite), length > 100 else { return nil }
        self.length = length; self.departureElevation = departureElevation; self.arrivalElevation = arrivalElevation
        let top = max(departureElevation, arrivalElevation)
        // At 1,000 km/h, a smoothstep climb/descent stays within 15/12 m/s.
        let climbFactor = 1.5 * (1000.0 / 3.6) / 15
        let descentFactor = 1.5 * (1000.0 / 3.6) / 12
        let minimum = (top - departureElevation) * climbFactor + (top - arrivalElevation) * descentFactor
        guard minimum < length * 0.8 else { return nil }
        let headroom = (length * 0.8 - minimum) / (climbFactor + descentFactor)
        cruiseAltitude = top + min(max(600, 11_000 - top), headroom)
        climbLength = max(length * 0.1, (cruiseAltitude - departureElevation) * climbFactor)
        descentLength = max(length * 0.1, (cruiseAltitude - arrivalElevation) * descentFactor)
        guard climbLength + descentLength <= length else { return nil }
        // Envelope acceleration <= 1.5 m/s², plus at most 0.5 m/s²
        // from an in-flight cruise adjustment. Short flights fly more slowly.
        maximumSpeed = min(1000 / 3.6, sqrt(1.5 * min(climbLength, descentLength)))
    }
    func altitude(at distance: Double) -> Double {
        func smooth(_ x: Double) -> Double { x * x * (3 - 2*x) }
        if distance <= 0 { return departureElevation }
        if distance >= length { return arrivalElevation }
        if distance < climbLength {
            return departureElevation + (cruiseAltitude - departureElevation) * smooth(distance / climbLength)
        }
        if distance > length - descentLength {
            return arrivalElevation + (cruiseAltitude - arrivalElevation) * smooth((length - distance) / descentLength)
        }
        return cruiseAltitude
    }
    func envelope(at distance: Double) -> Double {
        let u = min(1, max(0, min(distance / climbLength, (length - distance) / descentLength)))
        return sqrt(max(0, u * (2-u)))
    }
    func clock(at distance: Double) -> Double {
        let x = min(length, max(0, distance))
        if x < climbLength { return climbLength * acos(1 - x / climbLength) }
        if x > length - descentLength {
            return totalClock - descentLength * acos(1 - (length - x) / descentLength)
        }
        return climbClock + x - climbLength
    }
    func distance(atClock value: Double) -> Double {
        let q = min(totalClock, max(0, value))
        if q < climbClock { return climbLength * (1 - cos(q / climbLength)) }
        if q > climbClock + cruiseLength {
            return length - descentLength * (1 - cos((totalClock - q) / descentLength))
        }
        return climbLength + q - climbClock
    }
}

struct FlightJourney {
    let plan: FlightPlan
    private(set) var distance = 0.0
    private(set) var elapsed = 0.0
    private(set) var cruiseKmh: Double
    private var scalar: Double
    private var target: Double
    private let acceleration = 0.5
    var progress: Double { distance / plan.path.length }
    var altitude: Double { plan.profile.altitude(at: distance) }
    var speed: Double { plan.profile.envelope(at: distance) * scalar }
    var remainingSeconds: Double { time(forClock: plan.profile.totalClock - plan.profile.clock(at: distance)) }
    var isFinished: Bool { distance >= plan.path.length }
    init(plan: FlightPlan, cruiseKmh: Double) {
        self.plan = plan
        let kmh = min(1000, max(300, cruiseKmh.isFinite ? cruiseKmh : 850))
        self.cruiseKmh = kmh
        scalar = min(kmh / 3.6, plan.profile.maximumSpeed); target = scalar
    }
    mutating func changeSpeed(_ kmh: Double) {
        guard kmh.isFinite else { return }
        cruiseKmh = min(1000, max(300, kmh))
        target = min(cruiseKmh / 3.6, plan.profile.maximumSpeed)
    }
    private func clock(after seconds: Double) -> Double {
        let ramp = abs(target - scalar) / acceleration
        let t = min(seconds, ramp), a = target >= scalar ? acceleration : -acceleration
        return scalar * t + 0.5 * a * t*t + target * max(0, seconds-ramp)
    }
    private func time(forClock q: Double) -> Double {
        guard q > 0 else { return 0 }
        let ramp = abs(target - scalar) / acceleration
        let rampClock = (scalar + target) * 0.5 * ramp
        if q >= rampClock { return ramp + (q - rampClock) / target }
        let a = target >= scalar ? acceleration : -acceleration
        // Stable quadratic root, including tiny distances near landing.
        return 2*q / (scalar + sqrt(max(0, scalar*scalar + 2*a*q)))
    }
    mutating func advance(seconds: Double) {
        guard seconds.isFinite, seconds > 0, !isFinished else { return }
        let remaining = remainingSeconds, t = min(seconds, remaining)
        let q = plan.profile.clock(at: distance) + clock(after: t)
        distance = seconds >= remaining ? plan.path.length : plan.profile.distance(atClock: q)
        let delta = acceleration * t
        scalar = target > scalar ? min(target, scalar + delta) : max(target, scalar - delta)
        elapsed += t
    }
    mutating func seek(_ fraction: Double) {
        guard fraction.isFinite else { return }
        distance = min(1, max(0, fraction)) * plan.path.length
        // Seeking is an explicit relocation; use the selected cruise setting at
        // the destination phase, rather than carrying an old acceleration ramp.
        scalar = target
    }
}
