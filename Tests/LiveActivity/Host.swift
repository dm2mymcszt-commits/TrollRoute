import SwiftUI
import ActivityKit

@main
struct LiveActivityQAApp: App {
    init() {
        SharedPreferences.defaults.set(false, forKey: RouteActivityPreference.key)
        SharedPreferences.defaults.set(true, forKey: "mapButtonLabels")
        SharedPreferences.defaults.set(false, forKey: "tapMapToSetLocation")
        try! qaFavorites.save(.init(name: "Activity test favorite", latitude: 45, longitude: 1))
    }
    var body: some Scene {
        WindowGroup { ActivityQAView().tint(.indigo).preferredColorScheme(.dark) }
    }
}

@MainActor
struct ActivityQAView: View {
    @ObservedObject private var engine = RouteRuntime.shared.simulator
    var body: some View {
        LocSimView().overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Button("Start real") { start(previous: false) }
                Button("Start spoof") { start(previous: true) }
                Button("Start flight") { startFlight() }
                Button("Seek 46") { engine.seek(to: 0.46) }
                Button("Speed 120") { engine.updateLiveSpeed(120) }
                Button("Disable activity") { RouteActivityPreferences.shared.enabled = false }
                Button("Enable activity") { RouteActivityPreferences.shared.enabled = true }
                Button("Return leg") {
                    engine.configureFinish(.init(action: .returnOnce))
                    engine.seek(to: 1)
                }
                Text(engine.isSimulating ? (engine.isPaused ? "QA paused" : "QA moving") : "QA stopped")
                if Activity<RouteActivityAttributes>.activities.contains(where: {
                    $0.attributes.tripID == engine.activitySnapshot?.tripID && $0.activityState == .active
                }) { Text("QA activity ready") } else { Text("QA no activity") }
                if QAFixture.shared.at(QAFixture.shared.c) { Text("QA at favorite") }
                Text("Samples \(QAFixture.shared.driver.samples.count)")
                if let message = RouteActivityPreferences.shared.message { Text(message) }
            }.font(.caption).padding(8).background(.regularMaterial).padding(.top, 40)
        }
    }
    private func startFlight() {
        engine.stopSimulation()
        let a = FlightAirport(id: "LFPG", name: "Paris Charles de Gaulle", city: "Paris", country: "FR",
            codes: ["CDG"], latitude: 49.0097, longitude: 2.5479, elevation: 119)
        let b = FlightAirport(id: "KJFK", name: "John F. Kennedy", city: "New York", country: "US",
            codes: ["JFK"], latitude: 40.6394, longitude: -73.7789, elevation: 4)
        let plan = try! FlightPlan(departure: a, arrival: b)
        engine.travelMode = .plane
        engine.routeStart = a.coordinate; engine.routeEnd = b.coordinate
        engine.availableRoutes = [RouteOption(route: RoutePath(flight: plan), index: 0)]
        engine.selectRoute(at: 0); engine.updateSpeedKmh(850, for: .plane)
        RouteActivityPreferences.shared.enabled = true
        engine.startSimulation()
        engine.seek(to: 0.5)
    }
    private func start(previous: Bool) {
        engine.stopSimulation()
        let fixture = QAFixture.shared
        if previous {
            fixture.owner.receive(RouteLocationSample.make(coordinate: fixture.c, altitude: 123,
                course: 0, speed: 0, timestamp: Date()), kind: .stationary, newIntent: true)
        }
        fixture.prepare()
        engine.updateSpeedKmh(20, for: .driving)
        RouteActivityPreferences.shared.enabled = true
        engine.startSimulation(startName: "Original start", destinationName: "Test destination")
    }
}
