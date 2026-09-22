import SwiftUI
import MapKit

struct EquatableCoordinate: Equatable {
    let coordinate: CLLocationCoordinate2D
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

struct WorkspacePreview: View {
    @ObservedObject private var mapObservation = WorkspaceMapObservation.shared
    @State private var region: MKCoordinateRegion? = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 44.8378, longitude: -0.5792),
        span: MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.07))
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showAltitude = false
    @StateObject private var altitude = AltitudeController(currentLocation: { nil }, deliver: { _ in })
    @State private var routeActive = false
    @StateObject private var mainStop = MainStopController()
    @StateObject private var longPressRoute = LongPressRouteController()
    @AppStorage("confirmBeforeStoppingSpoofing", store: SharedPreferences.defaults) private var confirmStop = true
    @State private var pressCount = 0
    @State private var tapCount = 0
    @State private var savedFavoriteName = "No favorite"
    @State private var lastAction = "none"
    @State private var tapped: EquatableCoordinate?
    // Deterministic address fixture for the confirmation screenshot, not a live lookup.
    @StateObject private var mapMove = MapMoveController(lookup: { _, completion in
        completion("Preview address, Bordeaux")
        return {}
    })
    @StateObject private var places = RouteRecentPlaces()
    @AppStorage("mapStyle", store: SharedPreferences.defaults) private var mapStyle = "standard"
    @AppStorage("tapMapToSetLocation", store: SharedPreferences.defaults) private var tapEnabled = false
    @AppStorage("askBeforeMoving", store: SharedPreferences.defaults) private var askBeforeMoving = true
    let screen: String
    let appearance: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CustomMapView(tappedCoordinate: $tapped, moveToRegion: $region,
                          allowsLocationSelection: tapEnabled, showsUserLocation: false, mapStyle: mapStyle,
                          proposedPosition: mapMove.pendingRequest?.coordinate,
                          onLongPress: screen == "gestures-long" ? { _ in pressCount += 1 }
                            : screen == "gestures-confirm" ? { point in
                                longPressRoute.request(destination: point, enabled: true, confirm: true,
                                    autoStart: false, spoofedStart: CLLocationCoordinate2D(latitude: 44.8, longitude: -0.6),
                                    routeRunning: false, lookup: { _ in {} }, create: { _ in pressCount += 1 })
                            } : nil)
                .ignoresSafeArea()
        }
        .frame(height: screen == "gestures-short" ? 240 : nil)
        .modifier(MapToolbarOverlay(onAction: { action in
            lastAction = action.rawValue
            if action == .settings { showSettings = true }
            if action == .search { showSearch = true }
            if action == .route { routeActive.toggle() }
            if action == .stop { mainStop.request(confirm: confirmStop, routeRunning: routeActive) { routeActive = false } }
        }, joystickActive: false, routeActive: routeActive))
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topLeading) {
            if screen.hasPrefix("gestures") {
                VStack(alignment: .leading) {
                Text("action=\(lastAction),confirmation=\(mainStop.presentedRequest != nil),running=\(routeActive)")
                    .accessibilityIdentifier("toolbar-state").allowsHitTesting(false)
                Text("Map state").accessibilityIdentifier("map-observation")
                    .accessibilityValue(mapObservation.value).allowsHitTesting(false)
                Text("presses=\(pressCount),taps=\(tapCount)")
                    .accessibilityIdentifier("gesture-counts").allowsHitTesting(false)
                }.font(.caption)
            }
            if screen == "favorites" {
                Text(savedFavoriteName)
                    .accessibilityIdentifier("saved-favorite").allowsHitTesting(false)
            }
        }
        .modifier(MapMoveConfirmation(controller: mapMove))
        .modifier(MainStopConfirmation(controller: mainStop))
        .modifier(LongPressRouteConfirmation(controller: longPressRoute))
        .onChange(of: tapped) { coordinate in
            guard let coordinate = coordinate else { return }
            tapped = nil
            if screen == "gestures-long" || screen == "gestures-confirm" { tapCount += 1; return }
            mapMove.request(coordinate.coordinate, displayCoordinate: coordinate.coordinate,
                            enabled: tapEnabled, ask: askBeforeMoving, routeRunning: routeActive) { _ in }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showAltitude) { AltitudeSheet(settings: .shared, controller: altitude) }
        .sheet(isPresented: $showSearch, onDismiss: {
            savedFavoriteName = (try? BookMarkRetrieve())?.last?["name"] as? String ?? "No favorite"
        }) {
            RouteLocationPicker(title: "Find a place", region: nil, selectedCoordinate: nil,
                recents: places, initialQuery: screen == "favorites" ? "44.817059, -0.585746" : "125 Cr Gambetta, 33400 Talence", select: { _ in })
        }
        .task {
            AltitudeSettings.shared.reset()
            if screen == "altitude-custom" { AltitudeSettings.shared.setCustom(250) }
            if screen == "altitude-negative" { AltitudeSettings.shared.setCustom(-12.5) }
            if screen.hasPrefix("altitude-") { showAltitude = true }
            tapEnabled = screen == "settings-enabled" || screen == "gestures-long" || screen == "gestures-confirm"
            if screen == "settings" || screen == "settings-enabled" { showSettings = true }
            if screen == "search" { showSearch = true }
            if screen == "favorites" { showSearch = true }
            if screen == "confirmation" {
                let point = CLLocationCoordinate2D(latitude: 44.8378, longitude: -0.5792)
                mapMove.request(point, displayCoordinate: point, enabled: true, ask: true,
                                routeRunning: true) { _ in }
            }
        }
        .preferredColorScheme(appearance == "dark" ? .dark : .light)
        .tint(.indigo)
    }
}

@main struct MapWorkspacePreview: App {
    init() {
        let args = ProcessInfo.processInfo.arguments
        SharedPreferences.defaults.set(!args.contains("--stop-without-confirmation"), forKey: "confirmBeforeStoppingSpoofing")
        if let index = args.firstIndex(of: "--labels"), index + 1 < args.count {
            SharedPreferences.defaults.set(args[index + 1] == "yes", forKey: "mapButtonLabels")
        } else { SharedPreferences.defaults.set(true, forKey: "mapButtonLabels") }
    }
    private func argument(_ key: String, fallback: String) -> String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return fallback }
        return args[index + 1]
    }
    var body: some Scene {
        WindowGroup {
            WorkspacePreview(screen: argument("--screen", fallback: "map"),
                             appearance: argument("--appearance", fallback: "dark"))
        }
    }
}

// Event-driven observation of the actual production MKMapView delegate.
// A published accessibility value invalidates XCTest's cached snapshot; a
// computed UIView getter alone does not notify accessibility when the map moves.
final class WorkspaceMapObservation: ObservableObject {
    static let shared = WorkspaceMapObservation()
    @Published var value = ""
    func changed(_ region: MKCoordinateRegion) {
        value = "\(region.center.latitude),\(region.center.longitude),\(region.span.latitudeDelta),\(region.span.longitudeDelta)"
    }
}
