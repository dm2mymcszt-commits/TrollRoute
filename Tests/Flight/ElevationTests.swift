import Foundation
import CoreLocation

@main struct AirportElevationTests {
    static func main() async throws {
        let suite = "airport-elevation-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let missing = FlightAirport(id: "MISSING", name: "Missing elevation", city: "", country: "XX", codes: [],
            latitude: 40, longitude: 2, elevation: nil)
        let resolver = AirportElevationResolver(defaults: defaults)
        let result = try await resolver.resolve(missing) { coordinate in
            precondition(coordinate.latitude == 40 && coordinate.longitude == 2)
            return 123
        }
        precondition(result.elevation == 123)
        let cached = try await resolver.resolve(missing) { _ in preconditionFailure("Cached airport must not query again") }
        precondition(cached == result)
        let restored = AirportElevationResolver(defaults: UserDefaults(suiteName: suite)!)
        let relaunched = try await restored.resolve(missing) { _ in preconditionFailure("Cache must survive relaunch") }
        precondition(relaunched == result)
        let known = try await resolver.resolve(missing.withElevation(30)) { _ in preconditionFailure("Bundled elevation needs no lookup") }
        precondition(known.elevation == 30)
        let unavailable = FlightAirport(id: "FAIL", name: "Unavailable", city: "", country: "XX", codes: [],
            latitude: 41, longitude: 3, elevation: nil)
        do {
            _ = try await resolver.resolve(unavailable) { _ in nil }
            preconditionFailure("Missing elevation must not silently become sea level")
        } catch FlightError.elevationUnavailable { }
        do {
            _ = try await resolver.resolve(unavailable) { _ in preconditionFailure("Brief failure cache must limit retries") }
            preconditionFailure("Cached failure should remain unavailable")
        } catch FlightError.elevationUnavailable { }
        print("PASS: known and missing airport elevations, persistent cache, no assumed sea level and bounded retries")
    }
}
