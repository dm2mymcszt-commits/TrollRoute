//  TrollRoute LocSim - Route Extension
//  Created by son3ra1n.

import SwiftUI
import MapKit
import AlertKit

struct RouteSimSheet: View {
    @AppStorage("mapStyle", store: SharedPreferences.defaults) private var mapStyle = "standard"
    @ObservedObject var routeSimulator: RouteSimulator
    @ObservedObject var draft: RouteDraft
    @Binding var mapRegion: MKCoordinateRegion?
    @Binding var isPresented: Bool
    
    @State private var startText: String = ""
    @State private var endText: String = ""
    @State private var startSource: SharedPlaceSource?
    @State private var endSource: SharedPlaceSource?
    @State private var startCoord: CLLocationCoordinate2D? = nil
    @State private var endCoord: CLLocationCoordinate2D? = nil
    @State private var selectedMode: TravelMode = .driving
    @StateObject private var currentLocation = RouteCurrentLocation()
    @StateObject private var recentPlaces = RouteRecentPlaces()
    @State private var pickerField: ActiveField?
    @State private var waitingForCurrentStart = false
    @State private var didInitializeStart = false
    @State private var loadedDraftRevision: UUID?
    @State private var routeReady: Bool = false
    @State private var showGPXPicker: Bool = false
    @State private var isStarting = false
    @StateObject private var preparation = RoutePreparationController()
    @State private var startRequestID = UUID()
    
    enum ActiveField: String, Identifiable {
        case start, end
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    RouteLocationAccessNotice()
                    // MARK: - Route Status (when simulating)
                    if routeSimulator.isSimulating {
                        simulationStatusCard
                        RouteFinishControls(configuration: finishBinding, active: true)
                            .padding(.horizontal)
                    } else {
                        // MARK: - Start Point
                        locationCard(
                            title: "Start Point",
                            icon: "play.circle.fill",
                            iconColor: .green,
                            text: startText,
                            selectedCoord: startCoord,
                            field: .start
                        )
                        if waitingForCurrentStart {
                            if currentLocation.isLocating {
                                ProgressView("Finding your current location…")
                            }
                            if let message = currentLocation.message {
                                Text(message).font(.caption).foregroundColor(.secondary).padding(.horizontal)
                                Button("Retry Current Location", action: useCurrentStart)
                            }
                        }
                        
                        Button(action: swapEndpoints) {
                            Image(systemName: "arrow.up.arrow.down.circle.fill")
                                .font(.title2)
                        }
                        .accessibilityLabel("Swap start and destination")
                        .disabled(waitingForCurrentStart || startCoord == nil || endCoord == nil)

                        // MARK: - End Point
                        locationCard(
                            title: "Destination",
                            icon: "flag.checkered.circle.fill",
                            iconColor: .red,
                            text: endText,
                            selectedCoord: endCoord,
                            field: .end
                        )
                        
                        RouteModeControls(
                            selectedMode: selectedMode,
                            duration: { mode in
                                routeSimulator.modeDuration(mode) ??
                                    (routeSimulator.modeErrors[mode] == nil ? "" : "No route")
                            },
                            speedKmh: Binding(
                                get: { routeSimulator.speedKmh(for: selectedMode) },
                                set: { routeSimulator.updateSpeedKmh($0, for: selectedMode) }
                            ),
                            select: { mode in
                                selectedMode = mode
                                routeSimulator.selectMode(mode)
                                routeReady = !routeSimulator.availableRoutes.isEmpty
                                showRouteOnMap()
                            }
                        )
                        .padding(.horizontal)
                        if let error = routeSimulator.modeErrors[selectedMode] {
                            Text(error).font(.caption).foregroundColor(.secondary).padding(.horizontal)
                        }

                        // MARK: - Calculate Button
                                Button(action: calculateRoute) {
                                    HStack {
                                        if routeSimulator.isCalculatingRoute {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                                        }
                                        Text(routeSimulator.isCalculatingRoute ? "Calculating..." : "Calculate Routes")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill((startCoord != nil && endCoord != nil) ?
                                                  Color.indigo : Color.gray)
                                    )
                                    .foregroundColor(.white)
                                    .font(.headline)
                                }
                        .disabled(startCoord == nil || endCoord == nil || routeSimulator.isCalculatingRoute)
                        .padding(.horizontal)
                        
                        // MARK: - Route Selection (shown after calculation)
                        if routeReady && !routeSimulator.availableRoutes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "map.fill")
                                        .foregroundColor(.accentColor)
                                    Text("Select Route")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(routeSimulator.availableRoutes.count) route(s)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)

                                routePreview

                                Text("Times use your simulation speed. Travel estimates are shown separately.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                
                                ForEach(Array(routeSimulator.availableRoutes.enumerated()), id: \.element.id) { idx, option in
                                    routeOptionCard(option: option, index: idx)
                                }
                                
                                RouteFinishControls(configuration: finishBinding, active: false)
                                    .padding(.horizontal)

                                // Start button
                                Button(action: startRoute) {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Start Route Simulation")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color.green)
                                    )
                                    .foregroundColor(.white)
                                    .font(.headline)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
                .disabled(routeSimulator.isCalculatingRoute || isStarting)
            }
            .navigationTitle("TrollRoute Navigation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        routeSimulator.requestRouteStop()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.red)
                            .font(.title3)
                    }
                    .opacity(routeSimulator.isSimulating ? 1 : 0)
                    .disabled(!routeSimulator.isSimulating)
                    .accessibilityLabel("Stop route")
                    .accessibilityIdentifier("navigation-toolbar-stop")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showGPXPicker = true }) {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.indigo)
                            .font(.title3)
                    }
                    .opacity(routeSimulator.isSimulating ? 0 : 1)
                    .disabled(routeSimulator.isSimulating)
                }
            }
            .sheet(item: $pickerField) { field in
                RouteLocationPicker(
                    title: field == .start ? "Start Point" : "Destination",
                    region: searchRegion,
                    selectedCoordinate: field == .start ? startCoord : endCoord,
                    recents: recentPlaces,
                    useCurrentLocation: field == .start ? useCurrentStart : nil,
                    select: { selectPlace($0, field: field) }
                )
            }
            .sheet(isPresented: $showGPXPicker) {
                GPXDocumentPicker { url in
                    guard let result = GPXParser.parse(url: url), !result.isEmpty else {
                        UIApplication.shared.alert(body: "Failed to parse GPX file or file is empty.")
                        return
                    }
                    
                    let coords = result.allCoordinates
                    if coords.count >= 2 {
                        waitingForCurrentStart = false
                        currentLocation.cancel()
                        invalidateRoute()
                        // Use first and last as start/end
                        startCoord = coords.first
                        endCoord = coords.last
                        startText = "GPX Start"
                        endText = "GPX End (\(coords.count) points)"
                        
                        // Fit map to route
                        let centerLat = coords.map { $0.latitude }.reduce(0, +) / Double(coords.count)
                        let centerLon = coords.map { $0.longitude }.reduce(0, +) / Double(coords.count)
                        mapRegion = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        )
                        
                        AlertKitAPI.present(title: "GPX Loaded! \(coords.count) pts", icon: .done, style: .iOS17AppleMusic, haptic: .success)
                    }
                }
            }
        }
        .modifier(RouteStopPresentation(simulator: routeSimulator))
        .onAppear { loadDraft() }
        .onChange(of: draft.revision) { _ in loadDraft() }
        .onChange(of: routeSimulator.isSimulating) { running in
            if !running && draft.needsRecalculation {
                invalidateRoute()
                draft.needsRecalculation = false
                if startCoord == nil { useCurrentStart() }
            }
        }
        .onDisappear {
            preparation.cancel()
            startRequestID = UUID()
            isStarting = false
            currentLocation.cancel()
            if let revision = loadedDraftRevision {
                draft.commitEdits(
                    start: startCoord.map { endpointPlace(name: startText, coordinate: $0, source: startSource) },
                    destination: endCoord.map { endpointPlace(name: endText, coordinate: $0, source: endSource) },
                    revision: revision)
            }
        }
        .onReceive(currentLocation.$location) { location in
            guard waitingForCurrentStart, let location = location else { return }
            startCoord = CoordTransform.wgs84ToGcj02(location.coordinate)
            startText = "Current Location"
            startSource = nil
            waitingForCurrentStart = false
            invalidateRoute()
        }
    }
    
    private func loadDraft() {
        if !didInitializeStart || loadedDraftRevision != draft.revision {
            didInitializeStart = true
            loadedDraftRevision = draft.revision
            preparation.cancel()
            currentLocation.cancel()
            waitingForCurrentStart = false
            if draft.start != nil || draft.destination != nil {
                startSource = draft.start?.sharedSource
                endSource = draft.destination?.sharedSource
                startCoord = draft.start?.coordinate
                startText = draft.start?.name ?? ""
                endCoord = draft.destination?.coordinate
                endText = draft.destination?.name ?? ""
                selectedMode = routeSimulator.travelMode
                if draft.needsRecalculation && !routeSimulator.isSimulating {
                    invalidateRoute()
                    draft.needsRecalculation = false
                } else { routeReady = !routeSimulator.availableRoutes.isEmpty }
                if startCoord == nil && !routeSimulator.isSimulating { useCurrentStart() }
                if let autoStart = draft.takeAutomaticPreparation(), !routeSimulator.isSimulating {
                    calculateRoute(autoStart: autoStart)
                }
            } else if !routeSimulator.availableRoutes.isEmpty {
                startCoord = routeSimulator.routeStart
                endCoord = routeSimulator.routeEnd
                startText = "Route Start"
                endText = "Destination"
                selectedMode = routeSimulator.travelMode
                routeReady = true
            } else if !routeSimulator.isSimulating {
                useCurrentStart()
            }
        }
    }

    private var routePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            CustomMapView(
                tappedCoordinate: .constant(nil), moveToRegion: .constant(nil),
                routePolyline: routeSimulator.routePolyline,
                allRoutePolylines: routeSimulator.allRoutePolylines,
                selectedRouteIndex: routeSimulator.selectedRouteIndex,
                routeETAs: routeSimulator.simulatedRouteETAs,
                allowsLocationSelection: false,
                onSelectRoute: { routeSimulator.selectRoute(at: $0) },
                fitsRoutes: true, showsUserLocation: false, mapStyle: mapStyle
            )
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Text("Tap a numbered route to select it. A is the start; B is the destination.")
                .font(.caption).foregroundColor(.secondary)
            if selectedMode == .cycling {
                Text("© [OpenStreetMap contributors](https://www.openstreetmap.org/copyright) · [Routing](https://routing.openstreetmap.de/about.html) · [Fix the map](https://www.openstreetmap.org/fixthemap)")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Route Option Card
    private func routeOptionCard(option: RouteOption, index: Int) -> some View {
        RouteChoiceCard(
            number: index + 1,
            name: option.name,
            roadName: option.route.name,
            distance: option.distanceText,
            roadETA: option.trafficTimeText,
            roadETALabel: option.route.trafficLabel,
            simulationETA: option.simulationTimeText(speedKmh: routeSimulator.speedKmh(for: selectedMode)),
            speed: formattedSpeed,
            isSelected: routeSimulator.selectedRouteIndex == index,
            select: { routeSimulator.selectRoute(at: index) }
        )
        .padding(.horizontal)
    }

    // MARK: - Simulation Status Card
    private var simulationStatusCard: some View {
        VStack(spacing: 16) {
            // Progress
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: selectedMode.icon)
                        .foregroundColor(.accentColor)
                    Text(routeSimulator.legName)
                        .font(.headline)
                    Spacer()
                    Text("\(Int(routeSimulator.progress * 100))%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                }
                
                ProgressView(value: routeSimulator.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                
                HStack {
                    Text("\(routeSimulator.remainingDistance) remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Remaining: \(routeSimulator.remainingTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            
            // Controls
            HStack(spacing: 20) {
                Button(action: {
                    routeSimulator.togglePause()
                }) {
                    HStack {
                        Image(systemName: routeSimulator.isPaused ? "play.fill" : "pause.fill")
                        Text(routeSimulator.isPaused ? "Resume" : "Pause")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.orange)
                    )
                    .foregroundColor(.white)
                    .font(.headline)
                }
                
                Button(action: {
                    routeSimulator.requestRouteStop()
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.red)
                    )
                    .foregroundColor(.white)
                    .font(.headline)
                }
                .accessibilityIdentifier("navigation-status-stop")
            }
            
            // Current position info
            if let pos = routeSimulator.currentPosition {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    Text(String(format: "%.5f, %.5f", pos.latitude, pos.longitude))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Location Card
    private func locationCard(
        title: String,
        icon: String,
        iconColor: Color,
        text: String,
        selectedCoord: CLLocationCoordinate2D?,
        field: ActiveField
    ) -> some View {
        Button { pickerField = field } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(iconColor).font(.title2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.caption).foregroundColor(.secondary)
                    Text(text.isEmpty ? "Choose a place" : text)
                        .font(.headline).foregroundColor(.primary)
                    if let source = field == .start ? startSource : endSource {
                        Text(source.title).font(.caption).foregroundColor(.secondary)
                    }
                    if field == .end && selectedCoord == nil {
                        Text("Search, recent places, or choose on map")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var finishBinding: Binding<RouteFinishConfiguration> {
        Binding(get: { routeSimulator.finishConfiguration }, set: routeSimulator.configureFinish)
    }

    // MARK: - Computed
    private var formattedSpeed: String {
        "\(Int(routeSimulator.speedKmh(for: selectedMode))) km/h"
    }
    
    // MARK: - Actions
    private var searchRegion: MKCoordinateRegion? {
        if let coordinate = startCoord {
            return MKCoordinateRegion(center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        }
        return mapRegion
    }

    private func invalidateRoute() {
        routeReady = false
        routeSimulator.clearCalculatedRoutes()
    }

    private func useCurrentStart() {
        invalidateRoute()
        startCoord = nil
        startText = "Current Location"
        startSource = nil
        waitingForCurrentStart = true
        currentLocation.request()
    }

    private func selectPlace(_ place: RoutePlace, field: ActiveField) {
        if field == .start {
            waitingForCurrentStart = false
            currentLocation.cancel()
            startCoord = place.coordinate
            startText = place.name
            startSource = place.sharedSource
        } else {
            endCoord = place.coordinate
            endText = place.name
            endSource = place.sharedSource
        }
        recentPlaces.remember(place)
        invalidateRoute()
    }

    private func endpointPlace(name: String, coordinate: CLLocationCoordinate2D,
                               source: SharedPlaceSource?) -> RoutePlace {
        var place = RoutePlace(name: name, coordinate: coordinate)
        place.sharedSource = source
        return place
    }

    private func swapEndpoints() {
        guard !waitingForCurrentStart, let start = startCoord, let end = endCoord else { return }
        currentLocation.cancel()
        draft.start = endpointPlace(name: startText, coordinate: start, source: startSource)
        draft.destination = endpointPlace(name: endText, coordinate: end, source: endSource)
        guard draft.swapEndpoints() else { return }
        startSource = draft.start?.sharedSource
        endSource = draft.destination?.sharedSource
        startCoord = draft.start?.coordinate
        endCoord = draft.destination?.coordinate
        startText = draft.start?.name ?? ""
        endText = draft.destination?.name ?? ""
        draft.needsRecalculation = false
        calculateRoute()
    }

    private func calculateRoute() {
        calculateRoute(autoStart: false)
    }

    private func calculateRoute(autoStart: Bool) {
        guard let start = startCoord, let end = endCoord else { return }
        preparation.prepare(autoStart: autoStart, calculate: { completion in
            routeSimulator.calculateRoutes(from: start, to: end, mode: selectedMode, completion: completion)
        }, ready: {
                routeReady = true
                showRouteOnMap()
        }, start: {
            guard isPresented else { return }
            routeSimulator.selectRoute(at: 0)
            startRoute()
        }, failure: { error in
            UIApplication.shared.alert(body: error ?? "Failed to calculate route")
        })
    }
    
    private func showRouteOnMap() {
        // Fit every alternative, including routes far outside the selected route.
        let rect = routeSimulator.allRoutePolylines.reduce(MKMapRect.null) {
            $0.union($1.boundingMapRect)
        }
        if !rect.isNull {
            let region = MKCoordinateRegion(rect.insetBy(dx: -rect.size.width * 0.2, dy: -rect.size.height * 0.2))
            mapRegion = region
        }
    }
    
    private func startRoute() {
        guard !isStarting, routeReady, !routeSimulator.availableRoutes.isEmpty else { return }
        isStarting = true
        let request = UUID()
        startRequestID = request
        Task { @MainActor in
            await RouteNotifications.shared.requestPermissionIfNeeded()
            guard startRequestID == request else { return }
            isStarting = false
            guard isPresented, routeReady, !routeSimulator.availableRoutes.isEmpty else { return }
            routeSimulator.startSimulation(startName: startText, destinationName: endText)
            guard routeSimulator.isSimulating else {
                UIApplication.shared.alert(body: routeSimulator.startError ?? "Unable to start this route.")
                return
            }
            isPresented = false
            AlertKitAPI.present(title: "Route Started!", icon: .done, style: .iOS17AppleMusic, haptic: .success)
        }
    }
}

struct RouteModeControls: View {
    let selectedMode: TravelMode
    let duration: (TravelMode) -> String
    @Binding var speedKmh: Double
    let select: (TravelMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(TravelMode.allCases, id: \.self) { mode in
                    Button { select(mode) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: mode.icon).font(.title2)
                            Text(mode.rawValue).font(.caption)
                            if !duration(mode).isEmpty {
                                Text(duration(mode)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedMode == mode ? Color.accentColor.opacity(0.15) : Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedMode == mode ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedMode == mode ? .accentColor : .primary)
                    .accessibilityAddTraits(selectedMode == mode ? [.isSelected] : [])
                }
            }
            HStack {
                Text("\(selectedMode.rawValue) speed").font(.headline)
                Spacer()
                Text("\(Int(speedKmh)) km/h").monospacedDigit()
            }
            HStack {
                Button { speedKmh = max(1, speedKmh - 1) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                    .accessibilityLabel("Decrease speed")
                Slider(value: $speedKmh, in: 1...500, step: 1).accessibilityLabel("Speed in kilometres per hour")
                Button { speedKmh = min(500, speedKmh + 1) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .accessibilityLabel("Increase speed")
            }
            Text("Saved for \(selectedMode.rawValue.lowercased()) trips.").font(.caption).foregroundColor(.secondary)
        }
    }
}

// Shared by route setup and the isolated simulator visual check.
struct RoutePlaybackPanel: View {
    let progress: Double
    let elapsed: String
    let remaining: String
    let remainingDistance: String
    let isPaused: Bool
    var legName = "Route in progress"
    @Binding var speedKmh: Double
    @Binding var collapsed: Bool
    let preview: (Double) -> Void
    let seek: (Double) -> Void
    let cancelSeek: () -> Void
    let pause: () -> Void
    let stop: () -> Void
    var finishActionTitle: String? = nil
    var editFinish: (() -> Void)? = nil
    var showsRoutingCredit = false
    @State private var draggedProgress: Double?
    @GestureState private var dragging = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { collapsed.toggle() } label: {
                    Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                }.accessibilityLabel(collapsed ? "Expand route controls" : "Collapse route controls")
                Text(legName)
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if collapsed { Text("\(Int(progress * 100))%").font(.caption).monospacedDigit() }
                Button(action: pause) { Image(systemName: isPaused ? "play.fill" : "pause.fill") }
                    .accessibilityLabel(isPaused ? "Resume route" : "Pause route")
                Button(action: stop) { Image(systemName: "stop.fill") }.accessibilityLabel("Stop route")
            }
            .buttonStyle(.borderless)
            if !collapsed {
                HStack {
                    Text("\(Int((draggedProgress ?? progress) * 100))%")
                    Spacer()
                    Text("Elapsed \(elapsed)")
                }.font(.caption).monospacedDigit()
                GeometryReader { geometry in
                    let width = max(1, geometry.size.width)
                    let fraction = draggedProgress ?? progress
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 5)
                        Capsule().fill(Color.accentColor).frame(width: width * fraction, height: 5)
                        Circle().fill(Color.accentColor).frame(width: 18, height: 18)
                            .offset(x: min(width - 18, max(0, width * fraction - 9)))
                    }
                    .frame(height: 32)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .updating($dragging) { _, state, _ in state = true }
                        .onChanged { value in
                            let fraction = min(1, max(0, value.location.x / width))
                            draggedProgress = fraction
                            preview(fraction)
                        }
                        .onEnded { value in
                            seek(min(1, max(0, value.location.x / width)))
                            draggedProgress = nil
                        })
                    .accessibilityElement()
                    .accessibilityLabel("Route progress")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
                    .accessibilityAdjustableAction { direction in
                        seek(min(1, max(0, progress + (direction == .increment ? 0.05 : -0.05))))
                    }
                }.frame(height: 32)
                HStack {
                    Text("\(remaining) remaining")
                    Spacer()
                    Text(remainingDistance)
                }.font(.caption).foregroundColor(.secondary).monospacedDigit()
                HStack {
                    Text("Speed").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(speedKmh)) km/h").monospacedDigit()
                }
                HStack(spacing: 12) {
                    Button { speedKmh = max(1, speedKmh - 1) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                        .accessibilityLabel("Decrease trip speed")
                    Slider(value: $speedKmh, in: 1...500, step: 1).accessibilityLabel("Trip speed in kilometres per hour")
                    Button { speedKmh = min(500, speedKmh + 1) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel("Increase trip speed")
                }
                if let title = finishActionTitle, let edit = editFinish {
                    Button(action: edit) {
                        HStack {
                            Text("When this route finishes")
                            Spacer()
                            Text(title).foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                        }.font(.caption)
                    }.accessibilityIdentifier("edit-route-finish")
                }
            } else {
                ProgressView(value: progress).tint(.accentColor)
            }
            if showsRoutingCredit {
                Text("© [OpenStreetMap contributors](https://www.openstreetmap.org/copyright) · [Routing](https://routing.openstreetmap.de/about.html) · [Fix the map](https://www.openstreetmap.org/fixthemap)")
                    .font(.caption2)
                    .accessibilityIdentifier("active-route-credit")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .onDisappear { cancelSeek() }
        .onChange(of: dragging) { active in
            if !active && draggedProgress != nil { draggedProgress = nil; cancelSeek() }
        }
        .onChange(of: collapsed) { _ in draggedProgress = nil; cancelSeek() }
    }
}

struct RouteChoiceCard: View {
    let number: Int
    let name: String
    let roadName: String
    let distance: String
    let roadETA: String
    var roadETALabel: String = "Real traffic"
    let simulationETA: String
    let speed: String
    let isSelected: Bool
    let select: () -> Void

    private var color: Color {
        let colors: [Color] = [.blue, .orange, .purple, .pink]
        return colors[(number - 1) % colors.count]
    }

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(color).clipShape(Circle())
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(name).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(color)
                        }
                    }
                    if !roadName.isEmpty {
                        Text(roadName).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                    Text("\(simulationETA) · \(distance)")
                        .font(.headline).foregroundColor(.primary)
                    Text("At \(speed) · \(roadETALabel): \(roadETA)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? color : Color(UIColor.separator), lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Route \(number), \(name), \(simulationETA) at \(speed), \(distance). \(roadETALabel): \(roadETA)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
