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
    @State private var companion: Activity<RouteActivityAttributes>?
    var body: some View {
        LocSimView().overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Button("Start real") { start(previous: false) }
                Button("Start spoof") { start(previous: true) }
                Button("Seek 46") { engine.seek(to: 0.46) }
                Button("Speed 120") { engine.updateLiveSpeed(120) }
                Button("Disable activity") { RouteActivityPreferences.shared.enabled = false }
                Button("Enable activity") { RouteActivityPreferences.shared.enabled = true }
                Button("Return leg") {
                    engine.configureFinish(.init(action: .returnOnce))
                    engine.seek(to: 1)
                }
                Button("Companion") {
                    guard let snapshot = engine.activitySnapshot else { return }
                    companion = try! Activity.request(attributes: RouteActivityAttributes(tripID: UUID()),
                        contentState: .init(route: snapshot, updatedAt: Date()), pushType: nil)
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
