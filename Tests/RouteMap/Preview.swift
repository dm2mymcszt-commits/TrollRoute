import SwiftUI
import MapKit

// Simulator-only app. The route geometry and displayed estimates below are synthetic
// Bordeaux fixtures, not live directions or traffic results. Both views are production code.
struct EquatableCoordinate: Equatable {
    let coordinate: CLLocationCoordinate2D
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

enum BordeauxFixture {
    static let trafficETAs = ["24 min", "23 min", "23 min"]
    static let distances = ["7.5 km", "7.8 km", "7.9 km"]
    static let simulations = [7_500.0, 7_800.0, 7_900.0].map {
        RouteSimulationMath.durationText(RouteSimulationMath.simulationSeconds(distance: $0, speed: 500 / 3.6))
    }
    static let roads = ["A630 Â· Pont d'Aquitaine", "A630 Â· MÃ©rignac", "Bordeaux centre"]

    static func routes(latitudeOffset: Double = 0) -> [MKPolyline] {
        let paths: [[(Double, Double)]] = [
            [(44.805, -0.553), (44.795, -0.536), (44.836, -0.516), (44.876, -0.520),
             (44.901, -0.532), (44.910, -0.548), (44.902, -0.575), (44.908, -0.606),
             (44.914, -0.645), (44.897, -0.657), (44.882, -0.652)],
            [(44.805, -0.553), (44.784, -0.566), (44.787, -0.598), (44.802, -0.619),
             (44.801, -0.646), (44.812, -0.676), (44.840, -0.687), (44.867, -0.680),
             (44.882, -0.652)],
            [(44.805, -0.553), (44.819, -0.574), (44.820, -0.598), (44.838, -0.606),
             (44.856, -0.611), (44.867, -0.630), (44.882, -0.652)]
        ]
        return paths.map { path in
            let coordinates = path.map { CLLocationCoordinate2D(latitude: $0.0 + latitudeOffset, longitude: $0.1) }
            return MKPolyline(coordinates: coordinates, count: coordinates.count)
        }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

// MapKit is permitted to request its renderer synchronously during insertion. Force
// that timing to guard against the original stale route identity / all-blue bug.
private final class InsertionProbeMap: MKMapView {
    struct Capture {
        let polyline: MKPolyline
        let color: UIColor?
        let width: CGFloat
        let alpha: CGFloat
    }
    var captures: [Capture] = []

    override func addOverlay(_ overlay: MKOverlay, level: MKOverlayLevel) {
        if let polyline = overlay as? MKPolyline,
           let renderer = delegate?.mapView?(self, rendererFor: overlay) as? MKPolylineRenderer {
            captures.append(Capture(polyline: polyline, color: renderer.strokeColor,
                                    width: renderer.lineWidth, alpha: renderer.alpha))
        }
        super.addOverlay(overlay, level: level)
    }
}

@MainActor private enum RouteMapChecks {
    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailure(description: message) }
    }

    private static func sameCoordinate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 0.000001 && abs(a.longitude - b.longitude) < 0.000001
    }

    static func verifyHostedMap() throws {
        func findMap(in view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            for child in view.subviews {
                if let map = findMap(in: child) { return map }
            }
            return nil
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let map = windows.compactMap({ findMap(in: $0) }).first else {
            throw CheckFailure(description: "The real SwiftUI preview did not host a map")
        }
        try require(abs(map.bounds.height - 340) < 1 && map.bounds.width > 300,
                    "The real map preview lost its normal iPhone layout size")
        let endpoints = map.annotations.compactMap { $0 as? RouteEndpointAnnotation }
        try require(endpoints.count == 2, "Hosted preview is missing its endpoints")
        for endpoint in endpoints {
            try require(map.bounds.insetBy(dx: 12, dy: 12).contains(map.convert(endpoint.coordinate, toPointTo: map)),
                        "Initial map fit left an endpoint outside the viewport")
        }
        let badges = map.annotations.compactMap { $0 as? RouteBadgeAnnotation }
        try require(badges.count == 3, "Hosted preview is missing route badges")
        for badge in badges {
            guard let view = map.view(for: badge), !view.isHidden else {
                throw CheckFailure(description: "A route badge is not visible in the initial map preview")
            }
            try require(map.bounds.contains(view.convert(view.bounds, to: map)),
                        "A route badge is clipped by the initial map viewport")
        }
    }

    static func run() throws -> String {
        var location: EquatableCoordinate?
        var selections: [Int] = []
        let originalRoutes = BordeauxFixture.routes()
        var parent = CustomMapView(
            tappedCoordinate: Binding(get: { location }, set: { location = $0 }),
            moveToRegion: .constant(nil), allRoutePolylines: originalRoutes,
            selectedRouteIndex: 1, routeETAs: BordeauxFixture.simulations,
            allowsLocationSelection: false, onSelectRoute: { selections.append($0) },
            fitsRoutes: true, showsUserLocation: false
        )
        let map = InsertionProbeMap(frame: CGRect(x: 0, y: 0, width: 358, height: 340))
        let coordinator = parent.makeCoordinator()
        coordinator.installTapRecognizers(on: map)
        let mapKitDoubleTap = UITapGestureRecognizer()
        mapKitDoubleTap.numberOfTapsRequired = 2
        try require(coordinator.singleTap?.numberOfTapsRequired == 1 && coordinator.doubleTapGuard?.numberOfTapsRequired == 2,
                    "Single/double tap guard was not installed")
        try require(coordinator.gestureRecognizer(coordinator.singleTap!, shouldRequireFailureOf: mapKitDoubleTap),
                    "Single tap does not wait for MapKit double tap failure")
        try require(coordinator.gestureRecognizer(coordinator.doubleTapGuard!, shouldRecognizeSimultaneouslyWith: mapKitDoubleTap),
                    "Double tap guard would block map zoom")
        map.delegate = coordinator
        coordinator.updateRoutes(on: map)
        try assertRoutes(map, coordinator: coordinator, routes: originalRoutes, selected: 1)
        try assertAnnotations(map, coordinator: coordinator, routes: originalRoutes,
                              selected: 1, etas: BordeauxFixture.simulations)

        // Selection updates existing geometry, ordering, endpoint markers and badge state.
        parent.selectedRouteIndex = 2
        coordinator.parent = parent
        map.captures.removeAll()
        coordinator.updateRoutes(on: map)
        try assertRoutes(map, coordinator: coordinator, routes: originalRoutes, selected: 2)
        try assertAnnotations(map, coordinator: coordinator, routes: originalRoutes,
                              selected: 2, etas: BordeauxFixture.simulations)

        // Recalculation can return the same number of routes and vertices at new locations.
        let replacementRoutes = BordeauxFixture.routes(latitudeOffset: 0.02)
        parent.allRoutePolylines = replacementRoutes
        coordinator.parent = parent
        map.captures.removeAll()
        coordinator.updateRoutes(on: map)
        try assertRoutes(map, coordinator: coordinator, routes: replacementRoutes, selected: 2)
        try assertAnnotations(map, coordinator: coordinator, routes: replacementRoutes,
                              selected: 2, etas: BordeauxFixture.simulations)
        try require(!map.overlays.contains { overlay in originalRoutes.contains { $0 === overlay as AnyObject } },
                    "Recalculation retained obsolete route geometry")

        // Changing speed from 500 to 250 km/h refreshes every badge using the
        // same geometry; no new directions response is supplied.
        parent.routeETAs = [7_500.0, 7_800.0, 7_900.0].map {
            RouteSimulationMath.durationText(RouteSimulationMath.simulationSeconds(distance: $0, speed: 250 / 3.6))
        }
        map.captures.removeAll()
        coordinator.parent = parent
        coordinator.updateRoutes(on: map)
        try require(map.captures.isEmpty, "Changing speed replaced route geometry")
        try assertAnnotations(map, coordinator: coordinator, routes: replacementRoutes,
                              selected: 2, etas: parent.routeETAs)

        let badge = map.annotations.compactMap { $0 as? RouteBadgeAnnotation }.first { $0.routeIndex == 0 }!
        let badgeView = coordinator.mapView(map, viewFor: badge)!
        coordinator.mapView(map, didSelect: badgeView)
        try require(selections == [0], "Numbered badge did not select its matching route")

        // Exercise the production polyline hit test at a uniquely routed segment.
        // Annotations are removed only from this test map so they cannot intercept the sample tap.
        map.removeAnnotations(map.annotations)
        let route = replacementRoutes[1]
        let midpoint = MKMapPoint(x: (route.points()[4].x + route.points()[5].x) / 2,
                                  y: (route.points()[4].y + route.points()[5].y) / 2).coordinate
        coordinator.handleMapTap(at: map.convert(midpoint, toPointTo: map), on: map)
        try require(selections == [0, 1], "Tapping an alternative line did not select that route")
        try require(location == nil, "Route selection unexpectedly changed the simulated location")
        coordinator.handleMapTap(at: CGPoint(x: 5, y: 5), on: map)
        try require(location == nil, "The route preview allowed a background tap to select a location")

        // Removing all routes must remove both overlays and their map labels.
        parent.allRoutePolylines = []
        coordinator.parent = parent
        coordinator.updateRoutes(on: map)
        try require(map.overlays.isEmpty, "Clearing routes left stale map lines")
        try require(map.annotations.filter { !($0 is MKUserLocation) }.isEmpty,
                    "Clearing routes left stale markers")
        // Main-map safety is the default; opt-in coordinate selection remains available.
        let defaults = CustomMapView(tappedCoordinate: .constant(nil), moveToRegion: .constant(nil))
        try require(!defaults.allowsLocationSelection, "Map taps must be disabled by default")
        parent.allowsLocationSelection = true
        coordinator.parent = parent
        coordinator.handleMapTap(at: CGPoint(x: 20, y: 20), on: map)
        try require(location != nil, "Explicit map-tap opt-in failed")
        location = nil
        parent.proposedPosition = CLLocationCoordinate2D(latitude: 44.84, longitude: -0.58)
        coordinator.parent = parent
        coordinator.updateProposedPosition(on: map)
        try require(map.annotations.contains { $0 is ProposedPositionAnnotation }, "Proposed move pin missing")
        try require(location == nil, "Showing a proposed pin changed location")
        parent.proposedPosition = nil
        coordinator.parent = parent
        coordinator.updateProposedPosition(on: map)
        try require(!map.annotations.contains { $0 is ProposedPositionAnnotation }, "Cancel left a proposed pin")
        return "PASS: initial renderer colors, selected overlay ordering, A/B endpoints, numbered ETA badges, selection changes, same-count geometry replacement, ETA refresh, badge/line taps, location protection, and route clearing."
    }

    private static func assertRoutes(_ map: InsertionProbeMap, coordinator: CustomMapView.Coordinator,
                                     routes: [MKPolyline], selected: Int) throws {
        let overlays = map.overlays.compactMap { $0 as? MKPolyline }
        try require(overlays.count == routes.count, "Incorrect number of map route overlays")
        try require(overlays.last === routes[selected], "Selected route is not drawn above alternatives")
        try require(map.captures.count == routes.count, "Insertion renderer probe did not observe each route")
        let colors: [UIColor] = [.systemBlue, .systemOrange, .systemPurple]
        for (index, route) in routes.enumerated() {
            guard let insertion = map.captures.first(where: { $0.polyline === route }) else {
                throw CheckFailure(description: "No insertion renderer for route \(index + 1)")
            }
            try require(insertion.color?.isEqual(colors[index]) == true,
                        "Route \(index + 1) had wrong color during overlay insertion")
            try require(insertion.width == (index == selected ? 7 : 5),
                        "Route \(index + 1) had stale selection width during overlay insertion")
            try require(abs(insertion.alpha - (index == selected ? 1 : 0.85)) < 0.001,
                        "Route \(index + 1) had stale selection opacity during overlay insertion")
            let renderer = coordinator.mapView(map, rendererFor: route) as! MKPolylineRenderer
            try require(renderer.strokeColor?.isEqual(colors[index]) == true,
                        "Route \(index + 1) renderer lost its color")
        }
    }

    private static func assertAnnotations(_ map: MKMapView, coordinator: CustomMapView.Coordinator,
                                          routes: [MKPolyline], selected: Int, etas: [String]) throws {
        let endpoints = map.annotations.compactMap { $0 as? RouteEndpointAnnotation }
        try require(endpoints.count == 2, "Expected one start and one destination marker")
        for isStart in [true, false] {
            guard let endpoint = endpoints.first(where: { $0.isStart == isStart }) else {
                throw CheckFailure(description: "Missing route endpoint")
            }
            let route = routes[selected]
            let expected = route.points()[isStart ? 0 : route.pointCount - 1].coordinate
            try require(sameCoordinate(endpoint.coordinate, expected), "Endpoint marker is not at the selected route endpoint")
            let view = coordinator.mapView(map, viewFor: endpoint) as! MKMarkerAnnotationView
            try require(view.glyphText == (isStart ? "A" : "B"), "Endpoint marker lost its A/B label")
        }
        let badges = map.annotations.compactMap { $0 as? RouteBadgeAnnotation }
        try require(badges.count == routes.count, "Expected one numbered badge per route")
        for index in routes.indices {
            guard let badge = badges.first(where: { $0.routeIndex == index }) else {
                throw CheckFailure(description: "Missing numbered route badge")
            }
            try require(badge.eta == etas[index], "Route badge displays another route's ETA")
            let view = coordinator.mapView(map, viewFor: badge) as! RouteBadgeAnnotationView
            let labels = view.subviews.compactMap { ($0 as? UILabel)?.text }
            try require(labels.contains(String(index + 1)) && labels.contains(etas[index]),
                        "Route badge does not visibly show its number and ETA")
            try require(view.accessibilityTraits.contains(.selected) == (index == selected),
                        "Route badge selection does not match the selected route")
        }
    }
}

private struct RouteMapFixtureView: View {
    @State private var selected = 0
    @State private var mode: TravelMode = .driving
    @State private var modeSpeeds = Dictionary(uniqueKeysWithValues: TravelMode.allCases.map { ($0, $0.defaultSpeedKmh) })
    private let routes = BordeauxFixture.routes()
    private let arguments = ProcessInfo.processInfo.arguments

    private func argument(_ name: String, fallback: String) -> String {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return fallback }
        return arguments[index + 1]
    }

    var body: some View {
        let appearance = argument("--appearance", fallback: "dark")
        let section = argument("--section", fallback: "map")
        let displaySpeed = section == "modes" ? modeSpeeds[mode]! : 500
        let distances = fixtureDistances(section == "modes" ? mode : .driving)
        let etas = distances.map { RouteSimulationMath.durationText($0 / (displaySpeed / 3.6)) }
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if section == "modes" {
                            RouteModeControls(selectedMode: mode, duration: { mode in
                                RouteSimulationMath.durationText(RouteSimulationMath.simulationSeconds(
                                    distance: fixtureDistances(mode)[0],
                                    speed: modeSpeeds[mode]! / 3.6))
                            }, speedKmh: Binding(get: { modeSpeeds[mode]! }, set: { modeSpeeds[mode] = $0 }), select: { mode = $0 })
                        }
                        HStack {
                            Label("Select Route", systemImage: "map.fill").font(.headline)
                            Spacer()
                            Text("3 routes").font(.caption).foregroundColor(.secondary)
                        }
                        CustomMapView(
                            tappedCoordinate: .constant(nil), moveToRegion: .constant(nil),
                            allRoutePolylines: routes, selectedRouteIndex: selected,
                            routeETAs: etas, allowsLocationSelection: false,
                            onSelectRoute: { selected = $0 }, fitsRoutes: true, showsUserLocation: false
                        )
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        Text("Tap a numbered route to select it. A is the start; B is the destination.")
                            .font(.caption).foregroundColor(.secondary)
                        ForEach(0..<3, id: \.self) { index in
                            RouteChoiceCard(
                                number: index + 1,
                                name: index == 0 ? "Fastest Route" : "Alternative \(index)",
                                roadName: BordeauxFixture.roads[index], distance: String(format: "%.1f km", distances[index] / 1000),
                                roadETA: BordeauxFixture.trafficETAs[index], simulationETA: etas[index],
                                speed: "\(Int(displaySpeed)) km/h", isSelected: selected == index,
                                select: { selected = index }
                            )
                        }
                        Text("Synthetic Bordeaux routes Â· Visual QA fixture")
                            .font(.caption2).foregroundColor(.secondary).id("bottom")
                    }
                    .padding(16)
                }
                .task {
                    var report: String
                    do { report = try RouteMapChecks.run() }
                    catch { report = "FAIL: \(error)" }
                    // Allow the map to lay out and its tiles to load before the capture signal.
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if report.hasPrefix("PASS:") {
                        do { try RouteMapChecks.verifyHostedMap() }
                        catch { report = "FAIL: \(error)" }
                    }
                    if section == "cards" {
                        selected = 2
                        reader.scrollTo("bottom", anchor: .bottom)
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    try? report.write(to: documents.appendingPathComponent("route-map-\(appearance)-\(section).txt"),
                                      atomically: true, encoding: .utf8)
                }
            }
            .navigationTitle("Bordeaux Â· QA fixture")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(appearance == "dark" ? .dark : .light)
    }

    private func fixtureDistances(_ mode: TravelMode) -> [Double] {
        switch mode {
        case .walking: return [5_000, 5_500, 5_900]
        case .cycling: return [6_000, 6_500, 7_000]
        case .driving: return [7_500, 7_800, 7_900]
        case .train, .plane: return [50_000, 55_000, 59_000]
        }
    }
}

private struct PlaybackFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct PlaybackFixture: View {
    let appearance: String
    let section: String
    @State private var collapsed: Bool
    @State private var paused = false
    @State private var trip: RouteJourney
    @State private var previewPosition: CLLocationCoordinate2D?
    @State private var frames: [String: CGRect] = [:]
    private let routes = BordeauxFixture.routes()

    init(appearance: String, section: String) {
        self.appearance = appearance
        self.section = section
        _collapsed = State(initialValue: section == "collapsed")
        let polyline = BordeauxFixture.routes()[0]
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: coords.count))
        var trip = RouteJourney(track: RouteTrack(coordinates: coords)!, speedKmh: 120)
        trip.advance(seconds: 60)
        trip.seek(0.46)
        _trip = State(initialValue: trip)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CustomMapView(tappedCoordinate: .constant(nil), moveToRegion: .constant(nil),
                allRoutePolylines: routes, movingPosition: trip.motion(paused: paused).coordinate,
                routeETAs: routes.map { line in
                    var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: line.pointCount)
                    line.getCoordinates(&coords, range: NSRange(location: 0, length: coords.count))
                    return RouteSimulationMath.durationText(RouteTrack(coordinates: coords)!.length / (trip.speedKmh / 3.6))
                }, allowsLocationSelection: false,
                fitsRoutes: true, showsUserLocation: false, proposedPosition: previewPosition,
                proposalIsRoutePreview: previewPosition != nil)
                .ignoresSafeArea(.container, edges: .top)
            ScrollView(showsIndicators: false) {
                FloatingQuickMenu(onAction: { _ in }, joystickActive: false, routeActive: true)
                    .padding(.trailing, 12).padding(.top, 12)
            }.frame(width: 156)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: PlaybackFrames.self, value: ["menu": geometry.frame(in: .global)])
                })
        }
        .safeAreaInset(edge: .bottom) {
            RoutePlaybackPanel(progress: trip.progress,
                elapsed: RouteSimulationMath.durationText(trip.elapsed),
                remaining: RouteSimulationMath.durationText(trip.remainingSeconds),
                remainingDistance: String(format: "%.1f km", trip.remainingDistance / 1000), isPaused: paused,
                speedKmh: Binding(get: { trip.speedKmh }, set: { trip.changeSpeed($0) }),
                collapsed: $collapsed,
                preview: { previewPosition = trip.track.position(at: trip.track.length * $0).coordinate },
                seek: { trip.seek($0); previewPosition = nil }, cancelSeek: { previewPosition = nil },
                pause: { paused.toggle() }, stop: { paused = true },
                finishActionTitle: "Drive back to start", editFinish: {}, showsRoutingCredit: true)
                .padding(.horizontal, 12).padding(.bottom, 6)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: PlaybackFrames.self, value: ["panel": geometry.frame(in: .global)])
                })
        }
        .onPreferenceChange(PlaybackFrames.self) { frames = $0 }
        .preferredColorScheme(appearance == "dark" ? .dark : .light)
        .tint(.indigo)
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            let report: String
            if let menu = frames["menu"], let panel = frames["panel"],
               menu.height > 0, panel.height > 0, menu.maxY <= panel.minY + 1 {
                report = "PASS: main-map route controls and side menu do not overlap (\(section))"
            } else { report = "FAIL: route control/menu geometry \(frames)" }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? report.write(to: documents.appendingPathComponent("route-map-\(appearance)-\(section).txt"), atomically: true, encoding: .utf8)
        }
    }
}

@main struct RouteMapPreview: App {
    private func argument(_ key: String, fallback: String) -> String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), args.indices.contains(i + 1) else { return fallback }
        return args[i + 1]
    }
    var body: some Scene {
        WindowGroup {
            let section = argument("--section", fallback: "map")
            if section == "playback" || section == "collapsed" {
                PlaybackFixture(appearance: argument("--appearance", fallback: "dark"), section: section)
            } else { RouteMapFixtureView() }
        }
    }
}
