import Foundation
import CoreLocation

func close(_ a: Double, _ b: Double, _ tolerance: Double = 0.001) {
    precondition(a.isFinite && b.isFinite && abs(a-b) <= tolerance, "\(a) != \(b)")
}
func airport(_ id: String, _ lat: Double, _ lon: Double, _ elevation: Double) -> FlightAirport {
    FlightAirport(id: id, name: "Airport \(id)", city: "City \(id)", country: "XX", codes: [id],
        latitude: lat, longitude: lon, elevation: elevation)
}
let paris = airport("CDG", 49.0097, 2.5479, 119)
let tokyo = airport("HND", 35.5494, 139.7798, 6)
let plan = try FlightPlan(departure: paris, arrival: tokyo)
precondition(plan.path.length > 9_000_000 && plan.path.length < 10_000_000)
let catalog = AirportCatalog(airports: [tokyo, paris])
precondition(catalog.nearest(to: .init(latitude: 48.86, longitude: 2.35)) == paris)
precondition(catalog.search("cdg") == [paris] && catalog.search("City HND") == [tokyo])
let ties = AirportCatalog(airports: [airport("Z", 0, 0, 0), airport("A", 0, 0, 0)])
precondition(ties.nearest(to: .init(latitude: 1, longitude: 0))?.id == "A")
let dateLine = GreatCircle(from: .init(latitude: 0, longitude: 179), to: .init(latitude: 0, longitude: -179))!
close(dateLine.length, 222390.16, 1)
close(abs(dateLine.position(0.5).coordinate.longitude), 180)
close(dateLine.position(0.5).course, 90)
let pairs: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] = [
    (paris.coordinate, tokyo.coordinate),
    (.init(latitude: 89, longitude: -90), .init(latitude: 89, longitude: 90)),
    (.init(latitude: 0, longitude: 0), .init(latitude: 0, longitude: 180)),
    (.init(latitude: -33.9, longitude: 151.2), .init(latitude: 40.7, longitude: -74)),
    (.init(latitude: 10, longitude: 10), .init(latitude: 10.0001, longitude: 10.0001))]
for (a, b) in pairs {
    let arc = GreatCircle(from: a, to: b)!
    close(arc.position(0).coordinate.latitude, a.latitude)
    close(arc.position(1).coordinate.longitude, b.longitude)
    var sum = 0.0
    for i in 1...1000 {
        let previous = arc.position(Double(i-1)/1000), current = arc.position(Double(i)/1000)
        precondition(CLLocationCoordinate2DIsValid(current.coordinate) && (0..<360).contains(current.course))
        sum += GreatCircle.angularDistance(previous.coordinate, current.coordinate) * GreatCircle.radius
    }
    close(sum, arc.length, 0.1)
}
for pair in [(paris, tokyo), (paris, airport("ORY", 48.7233, 2.3794, 89)),
             (airport("SEA", 47.45, -122.31, 130), airport("YVR", 49.19, -123.18, 4))] {
    let flight = try FlightPlan(departure: pair.0, arrival: pair.1), p = flight.profile
    close(p.altitude(at: 0), pair.0.elevation!)
    close(p.altitude(at: p.length), pair.1.elevation!)
    close(p.envelope(at: 0), 0); close(p.envelope(at: p.length), 0)
    for boundary in [p.climbLength, p.length-p.descentLength] {
        close(p.altitude(at: boundary-0.001), p.altitude(at: boundary+0.001), 0.001)
        close(p.envelope(at: boundary-0.001), p.envelope(at: boundary+0.001), 0.0001)
    }
    for i in 0...1000 {
        let x = p.length * Double(i)/1000
        close(p.distance(atClock: p.clock(at: x)), x, 0.001)
    }
    for phase in [0.0, 0.03, 0.5, 0.98] {
        for setting in [300.0, 850, 1000] {
            var journey = FlightJourney(plan: flight, cruiseKmh: 850)
            journey.seek(phase)
            let height = journey.altitude, speed = journey.speed, position = journey.distance
            journey.changeSpeed(setting)
            close(journey.altitude, height); close(journey.speed, speed); close(journey.distance, position)
            let eta = journey.remainingSeconds
            var stepped = journey
            var lastSpeed = stepped.speed, lastHeight = stepped.altitude, measured = 0.0
            while !stepped.isFinished {
                let step = min(0.5, stepped.remainingSeconds)
                precondition(step > 0)
                stepped.advance(seconds: step)
                measured += step
                precondition(abs(stepped.speed-lastSpeed) <= 2.01*step + 0.001)
                precondition(abs(stepped.altitude-lastHeight) <= 15.01*step + 0.001)
                lastSpeed = stepped.speed; lastHeight = stepped.altitude
            }
            close(measured, eta, 0.02)
            journey.advance(seconds: eta + 1)
            precondition(journey.isFinished)
            close(journey.speed, 0); close(journey.altitude, pair.1.elevation!)
            close(journey.elapsed, eta, 0.001)
            journey.seek(0.2)
            precondition(!journey.isFinished && journey.remainingSeconds > 0)
        }
    }
    let reverse = try flight.reversed()
    close(reverse.path.length, flight.path.length)
    close(reverse.profile.altitude(at: 0), pair.1.elevation!)
    close(reverse.profile.altitude(at: reverse.path.length), pair.0.elevation!)
}
let short = try FlightPlan(departure: paris, arrival: airport("ORY", 48.7233, 2.3794, 89))
precondition(short.profile.cruiseAltitude < plan.profile.cruiseAltitude)
precondition(FlightProfile(length: 500, departureElevation: 0, arrivalElevation: 4000) == nil)
do { _ = try FlightPlan(departure: paris, arrival: paris); preconditionFailure("Same airport must be rejected") }
catch FlightError.sameAirport { }
let bundled = try AirportCatalog(data: Data(contentsOf: URL(fileURLWithPath: "TrollRoute/Resources/Airports.json")))
precondition(bundled.airports.count == 4134)
precondition(bundled.search("CDG").contains { $0.id == "LFPG" })
print("PASS: bundled airports, nearest choice, search, global great circles, profiles, continuity, acceleration, vertical rates, seeking, live speed changes, exact ETA and reverse flights")
