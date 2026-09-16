import SwiftUI
import MapKit

struct EquatableCoordinate: Equatable {
    let coordinate: CLLocationCoordinate2D
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

// Error presentation remains real UIKit. Only the decorative AlertKit success
// toasts are excluded from this standalone host; route/view logic is unmodified.
extension UIApplication {
    func alert(body: String) {
        let alert = UIAlertController(title: "TrollRoute", message: body, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first?
            .rootViewController?.present(alert, animated: true)
    }
}

struct SessionHost: View {
    let fixture: EngineFixture
    @ObservedObject var engine: RouteSimulator
    @ObservedObject var owner: LocationSession
    @StateObject private var draft = RouteDraft()
    @State private var region: MKCoordinateRegion?
    @State private var navigation: Bool
    @State private var finish = false
    @State private var collapsed = false

    init(fixture: EngineFixture, navigation: Bool) {
        self.fixture = fixture
        engine = fixture.engine
        owner = fixture.owner
        _navigation = State(initialValue: navigation)
    }
    var body: some View {
        CustomMapView(tappedCoordinate: .constant(nil), moveToRegion: $region,
            allRoutePolylines: engine.displayedPolylines, movingPosition: engine.currentPosition,
            routeETAs: engine.simulatedRouteETAs, allowsLocationSelection: false,
            fitsRoutes: true, showsUserLocation: false, proposedPosition: engine.previewPosition,
            proposalIsRoutePreview: engine.previewPosition != nil)
            .ignoresSafeArea(.container, edges: engine.isSimulating ? .top : .all)
            .modifier(MapToolbarOverlay(onAction: { action in
                if action == .route { navigation = true }
            }, joystickActive: false, routeActive: engine.isSimulating))
            .safeAreaInset(edge: .bottom) {
                if engine.isSimulating {
                    RoutePlaybackPanel(progress: engine.progress, elapsed: engine.elapsedTime,
                        remaining: engine.remainingTime, remainingDistance: engine.remainingDistance,
                        isPaused: engine.isPaused, legName: engine.legName,
                        speedKmh: Binding(get: { engine.currentSpeedKmh }, set: engine.updateLiveSpeed),
                        collapsed: $collapsed, preview: engine.previewSeek, seek: engine.seek,
                        cancelSeek: engine.cancelSeek, pause: engine.togglePause, stop: engine.requestRouteStop,
                        finishActionTitle: engine.finishConfiguration.action.title,
                        editFinish: { finish = true }, showsRoutingCredit: true)
                        .padding(.horizontal, 12).padding(.bottom, 6)
                }
            }
            .overlay(alignment: .topLeading) {
                // Test-only state observation. The engine and driver supply it.
                Text("running=\(engine.isSimulating),paused=\(engine.isPaused),active=\(owner.isActive),default=\(fixture.settings.action.rawValue),action=\(engine.finishConfiguration.action.rawValue),stops=\(fixture.driver.stops)")
                    .font(.system(size: 1)).frame(width: 1, height: 1)
                    .accessibilityIdentifier("session-state")
            }
            .modifier(RouteStopPresentation(simulator: engine, enabled: !navigation))
            .sheet(isPresented: $navigation) {
                RouteSimSheet(routeSimulator: engine, draft: draft, mapRegion: $region, isPresented: $navigation)
            }
            .sheet(isPresented: $finish) {
                NavigationView {
                    ScrollView {
                        RouteFinishControls(configuration: Binding(get: { engine.finishConfiguration }, set: engine.configureFinish), active: true)
                            .padding()
                    }.navigationTitle("Route finish").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { finish = false } } }
                }
            }
            .tint(.indigo)
    }
}

@main final class SessionUIApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var fixture: EngineFixture?
    func application(_ app: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let fixture = EngineFixture(realtime: true)
        self.fixture = fixture
        let arguments = ProcessInfo.processInfo.arguments
        SharedPreferences.defaults.set(false, forKey: "mapButtonLabels")
        if arguments.contains("--previous") {
            fixture.owner.receive(RouteLocationSample.make(coordinate: fixture.c, course: 0,
                speed: 0, timestamp: Date()), kind: .stationary, newIntent: true)
        }
        fixture.prepare()
        let navigation = arguments.contains("--navigation") || arguments.contains("--active-navigation")
        if !navigation || arguments.contains("--active-navigation") {
            fixture.engine.startSimulation()
            fixture.engine.seek(to: 0.2)
            fixture.engine.updateLiveSpeed(5)
        }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: SessionHost(fixture: fixture, navigation: navigation))
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
