//  TrollRoute LocSim
//  Created by son3ra1n.
//  Enhanced version of Geranium.
//  Developed by son3ra1n.
//

import SwiftUI
import CoreLocation
import MapKit
import AlertKit

struct LocSimView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var routeDraft = RouteDraft()
    @State private var incomingPlace: SharedPlaceRequest?
    @StateObject private var sharedChannel = SharedPlaceChannel()
    @State private var sharedEndpoint: SharedRouteDraft?
    @State private var presentingSharedID: UUID?
    @State private var sharedPlaceError: String?
    @AppStorage("mapStyle", store: SharedPreferences.defaults) private var mapStyle = "standard"
    @State private var routeControlsCollapsed = false
    @AppStorage("tapMapToSetLocation", store: SharedPreferences.defaults) private var tapMapToSetLocation = false
    @AppStorage("askBeforeMoving", store: SharedPreferences.defaults) private var askBeforeMoving = true
    @StateObject private var mapMove = MapMoveController()
    @StateObject private var mainStop = MainStopController()
    @StateObject private var longPressRoute = LongPressRouteController()
    @StateObject private var longPressLocation = RouteCurrentLocation()
    @AppStorage("longPressToCreateRoute", store: SharedPreferences.defaults) private var longPressToCreateRoute = true
    @AppStorage("confirmLongPressRoute", store: SharedPreferences.defaults) private var confirmLongPressRoute = false
    @AppStorage("autoStartLongPressRoute", store: SharedPreferences.defaults) private var autoStartLongPressRoute = false
    @AppStorage("confirmBeforeStoppingSpoofing", store: SharedPreferences.defaults) private var confirmBeforeStoppingSpoofing = true
    @StateObject private var routeSimulator = RouteSimulator()
    
    @ObservedObject private var locationSession = LocSimManager.session
    private var referenceCoordinate: CLLocationCoordinate2D {
        locationSession.current?.coordinate ?? locationSession.lastKnown?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
    @State private var showAltitude = false
    @State private var tappedCoordinate: EquatableCoordinate? = nil
    @State private var showRouteSheet: Bool = false
    @State private var showRouteFinish = false
    @State private var showSearchBar: Bool = false
    @State private var showSettings = false
    @StateObject private var recentPlaces = RouteRecentPlaces()
    @State private var mapRegion: MKCoordinateRegion? = nil
    
    // Joystick
    @State private var joystickActive: Bool = false
    
    // Favorites
    @State private var showFavorites: Bool = false
    
    var body: some View {
        LocSimMainView()
    }
    @ViewBuilder
        private func LocSimMainView() -> some View {
            ZStack(alignment: .topTrailing) {
                // MARK: - Main Map
                CustomMapView(tappedCoordinate: $tappedCoordinate, moveToRegion: $mapRegion,
                              routePolyline: routeSimulator.routePolyline,
                              allRoutePolylines: routeSimulator.displayedPolylines,
                              selectedRouteIndex: routeSimulator.isSimulating ? 0 : routeSimulator.selectedRouteIndex,
                              movingPosition: routeSimulator.currentPosition,
                              routeETAs: routeSimulator.simulatedRouteETAs,
                              allowsLocationSelection: tapMapToSetLocation,
                              onSelectRoute: { index in
                                  guard !routeSimulator.isSimulating else { return }
                                  routeSimulator.selectRoute(at: index)
                              }, mapStyle: mapStyle,
                              proposedPosition: mapMove.pendingRequest?.coordinate ?? routeSimulator.previewPosition,
                              proposalIsRoutePreview: mapMove.pendingRequest == nil && routeSimulator.previewPosition != nil,
                              onLongPress: longPressToCreateRoute ? requestLongPressRoute : nil)
                    .onAppear {
                        CLLocationManager().requestAlwaysAuthorization()
                    }
                    .onChange(of: tappedCoordinate) { newCoord in
                        guard let coord = newCoord else { return }
                        tappedCoordinate = nil
                        mapMove.request(coord.coordinate,
                            displayCoordinate: CoordTransform.gcj02ToWgs84(coord.coordinate),
                            enabled: tapMapToSetLocation, ask: askBeforeMoving,
                            routeRunning: routeSimulator.isSimulating) { coordinate in
                            startSimulation(at: coordinate)
                        }
                    }
                    // Keep MapKit's own attribution and viewport above playback.
                    .ignoresSafeArea(.container, edges: routeSimulator.isSimulating ? .top : .all)
                
            // MARK: - Joystick Overlay
            if joystickActive {
                JoystickView(
                    isActive: $joystickActive,
                    onMove: { newCoord in
                        let location = RouteLocationSample.make(coordinate: newCoord, course: -1, speed: -1, timestamp: Date())
                        locationSession.receive(location, kind: .joystick)
                    },
                    currentCoordinate: { referenceCoordinate }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            
        }
        .modifier(MapToolbarOverlay(onAction: handleQuickMenuAction,
                                    joystickActive: joystickActive, routeActive: routeSimulator.isSimulating))
        .safeAreaInset(edge: .bottom) {
          VStack(spacing: 4) {
            if routeSimulator.isSimulating {
                RoutePlaybackPanel(
                    progress: routeSimulator.progress, elapsed: routeSimulator.elapsedTime,
                    remaining: routeSimulator.remainingTime, remainingDistance: routeSimulator.remainingDistance,
                    isPaused: routeSimulator.isPaused,
                    legName: routeSimulator.legName,
                    speedKmh: Binding(get: { routeSimulator.currentSpeedKmh }, set: { routeSimulator.updateLiveSpeed($0) }),
                    collapsed: $routeControlsCollapsed,
                    preview: routeSimulator.previewSeek, seek: routeSimulator.seek,
                    cancelSeek: routeSimulator.cancelSeek, pause: routeSimulator.togglePause, stop: routeSimulator.requestRouteStop,
                    finishActionTitle: routeSimulator.finishConfiguration.action.title,
                    editFinish: { showRouteFinish = true },
                    showsRoutingCredit: routeSimulator.travelMode == .cycling
                ).padding(.horizontal, 12).padding(.bottom, 6)
            }
            if !routeSimulator.isSimulating && routeSimulator.travelMode == .cycling && !routeSimulator.availableRoutes.isEmpty {
                Text("© [OpenStreetMap contributors](https://www.openstreetmap.org/copyright) · [Routing](https://routing.openstreetmap.de/about.html) · [Fix the map](https://www.openstreetmap.org/fixthemap)")
                    .font(.caption2).padding(6).background(.regularMaterial)
            }
          }
        }
        .modifier(MapMoveConfirmation(controller: mapMove))
        .modifier(MainStopConfirmation(controller: mainStop))
        .modifier(LongPressRouteConfirmation(controller: longPressRoute))
        .modifier(RouteStopPresentation(simulator: routeSimulator, enabled: !showRouteSheet))
        .alert("Create route", isPresented: Binding(get: { longPressRoute.error != nil }, set: { if !$0 { longPressRoute.error = nil } })) {
            Button("OK", role: .cancel) { longPressRoute.error = nil }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } message: { Text(longPressRoute.error ?? "") }
        .overlay(alignment: .topLeading) {
            if longPressRoute.isLocating {
                HStack {
                    ProgressView("Finding route start…")
                    Button("Cancel") { longPressRoute.cancel() }
                }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(12)
            }
        }
        .onChange(of: longPressToCreateRoute) { _ in longPressRoute.cancel() }
        .onChange(of: confirmLongPressRoute) { _ in longPressRoute.cancel() }
        .onChange(of: autoStartLongPressRoute) { _ in longPressRoute.cancel() }
        .onChange(of: tapMapToSetLocation) { _ in mapMove.cancel() }
        .onChange(of: askBeforeMoving) { _ in mapMove.cancel() }
        .onAppear { sharedChannel.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { phase in sharedChannel.setActive(phase == .active) }
        .onReceive(sharedChannel.$revision) { _ in
            if locationSession.refreshShared() { joystickActive = false }
            offerSharedPlace()
        }
        .onReceive(locationSession.$error) { error in
            if let error = error { sharedPlaceError = error }
        }
        .onOpenURL { url in
            if SharedCommandURL.requestID(url) != nil { sharedChannel.wake() }
        }
        .onChange(of: routeSimulator.isSimulating) { running in
            if !running { showRouteFinish = false }
        }
        .sheet(isPresented: $showAltitude, onDismiss: offerSharedPlace) {
            AltitudeSheet(settings: .shared, controller: locationSession.altitudeController)
        }
        .sheet(isPresented: $showSettings, onDismiss: offerSharedPlace) { SettingsView() }
        .sheet(isPresented: $showSearchBar, onDismiss: offerSharedPlace) {
            RouteLocationPicker(title: "Find a place", region: mapRegion,
                selectedCoordinate: nil, recents: recentPlaces) { place in
                recentPlaces.remember(place)
                let coordinate = place.coordinate
                mapRegion = MKCoordinateRegion(center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                startSimulation(at: coordinate)
            }
        }
        .sheet(isPresented: $showRouteFinish, onDismiss: offerSharedPlace) {
            NavigationView {
                ScrollView {
                    RouteFinishControls(configuration: Binding(
                        get: { routeSimulator.finishConfiguration }, set: routeSimulator.configureFinish), active: true)
                        .padding()
                }
                .navigationTitle("Route finish")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showRouteFinish = false } } }
            }
        }
        .sheet(isPresented: $showRouteSheet, onDismiss: offerSharedPlace) {
            RouteSimSheet(routeSimulator: routeSimulator, draft: routeDraft, mapRegion: $mapRegion, isPresented: $showRouteSheet)
                .onAppear {
                    if let id = presentingSharedID {
                        do { try SharedPlaceInbox().acknowledgePresentation(id) }
                        catch { sharedPlaceError = error.localizedDescription }
                        presentingSharedID = nil
                    }
                }
        }
        .sheet(isPresented: $showFavorites, onDismiss: offerSharedPlace) {
            FavoritesView(isPresented: $showFavorites, currentLat: referenceCoordinate.latitude, currentLong: referenceCoordinate.longitude) { favLat, favLong, name in
                let coord = CoordTransform.wgs84ToGcj02(CLLocationCoordinate2D(latitude: favLat, longitude: favLong))
                let region = MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                mapRegion = region
                startSimulation(at: coord)
                AlertKitAPI.present(title: "📍 \(name)", icon: .done, style: .iOS17AppleMusic, haptic: .success)
            }
        }
        .sheet(item: $incomingPlace, onDismiss: offerSharedPlace) { request in
            IncomingPlaceView(request: request, routeRunning: routeSimulator.isSimulating,
                accept: { handleSharedPlace(request, accept: true) },
                cancel: { handleSharedPlace(request, accept: false) })
        }
        .alert("Shared location", isPresented: Binding(get: { sharedPlaceError != nil }, set: { if !$0 { sharedPlaceError = nil } })) {
            Button("OK", role: .cancel) { sharedPlaceError = nil }
        } message: { Text(sharedPlaceError ?? "") }

    }

    private func offerSharedPlace() {
        guard sharedChannel.isActive, presentingSharedID == nil else { return }
        do {
            let inbox = SharedPlaceInbox()
            let pending = try inbox.pendingRequests()
            var base: SharedRouteDraft? = routeDraft.start != nil || routeDraft.destination != nil
                ? SharedRouteDraft(start: routeDraft.start, destination: routeDraft.destination) : nil
            for request in pending where request.action == .start || request.action == .destination {
                if let saved = try inbox.consumeEndpoint(request.id, current: base) {
                    sharedEndpoint = saved
                    base = nil // Later queued endpoints build on the just-committed draft.
                    if let place = request.place { recentPlaces.remember(place) }
                }
            }
            if sharedEndpoint == nil {
                let saved = try inbox.routeDraft()
                if saved.presentation != nil { sharedEndpoint = saved }
            }
            if let endpoint = sharedEndpoint, let id = endpoint.presentation {
                mapMove.cancel(); longPressRoute.cancel()
                if let request = routeSimulator.stopRequest { routeSimulator.cancelRouteStop(request.id) }
                if showAltitude || showSettings || showSearchBar || showRouteSheet || showFavorites || showRouteFinish || incomingPlace != nil {
                    showAltitude = false; showSettings = false; showSearchBar = false
                    showRouteSheet = false; showFavorites = false; showRouteFinish = false; incomingPlace = nil
                    return // Actual dismissal completes before replacing the Navigation draft.
                }
                routeDraft.applySharedDraft(endpoint)
                if let place = endpoint.destination ?? endpoint.start {
                    mapRegion = MKCoordinateRegion(center: place.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                }
                presentingSharedID = id
                sharedEndpoint = nil
                showRouteSheet = true
                return
            }
            // Legacy Go requests keep their existing review until the direct-Go
            // command path is installed. Endpoint requests never enter this sheet.
            guard incomingPlace == nil, let request = pending.first(where: { $0.action == .go || $0.action == .favorite }) else { return }
            mapMove.cancel()
            if showAltitude || showSettings || showSearchBar || showRouteSheet || showFavorites || showRouteFinish {
                showAltitude = false; showSettings = false; showSearchBar = false
                showRouteSheet = false; showFavorites = false; showRouteFinish = false
                return
            }
            incomingPlace = request
        } catch { sharedPlaceError = error.localizedDescription }
    }

    private func handleSharedPlace(_ request: SharedPlaceRequest, accept: Bool) {
        do {
            // Remove before applying so activation cannot repeat an accepted move.
            try SharedPlaceInbox().remove(request)
            incomingPlace = nil
            guard accept, let place = request.place else { return }
            recentPlaces.remember(place)
            switch request.action {
            case .go:
                mapRegion = MKCoordinateRegion(center: place.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                startSimulation(at: place.coordinate)
            case .start, .destination:
                break // Consumed transactionally by the endpoint channel.
            case .favorite:
                try SharedPlaceInbox.saveFavorite(place)
            }
        } catch {
            incomingPlace = nil
            sharedPlaceError = error.localizedDescription
        }
    }
    
    private func startSimulation(at gcjCoordinate: CLLocationCoordinate2D) {
        longPressRoute.cancel()
        mapMove.cancel()
        if routeSimulator.isSimulating { routeSimulator.stopSimulation() }
        joystickActive = false
        let wgsCoordinate = CoordTransform.gcj02ToWgs84(gcjCoordinate)
        
        
        let location = RouteLocationSample.make(coordinate: wgsCoordinate, course: 0, speed: 0, timestamp: Date())
        locationSession.receive(location, kind: .stationary, newIntent: true)
        guard locationSession.error == nil else { return }
        
        
        AlertKitAPI.present(
            title: "Started!",
            icon: .done,
            style: .iOS17AppleMusic,
            haptic: .success
        )
    }
    
    // MARK: - Quick Menu Handler
    private func handleQuickMenuAction(_ action: QuickMenuAction) {
        longPressRoute.cancel()
        // A pending map proposal must not appear over a newly opened tool.
        mapMove.cancel()
        switch action {
        case .search:
            showSearchBar.toggle()
        case .favorites:
            showFavorites.toggle()
        case .joystick:
            if !joystickActive && routeSimulator.isSimulating {
                routeSimulator.stopSimulation()
            }
            if !joystickActive && !locationSession.claimForUserAction() { return }
            withAnimation(.spring(response: 0.3)) {
                joystickActive.toggle()
            }
        case .route:
            joystickActive = false
            showRouteSheet.toggle()
        case .altitude:
            showAltitude = true
        case .settings:
            showSettings = true
        case .stop:
            mainStop.request(confirm: confirmBeforeStoppingSpoofing,
                             routeRunning: routeSimulator.isSimulating, stop: stopSimulation)
        }
    }
    
    private func stopSimulation() {
        longPressRoute.cancel()
        mapMove.cancel()
        routeSimulator.stopSimulation()
        joystickActive = false
        AlertKitAPI.present(title: "Stopped!", icon: .done, style: .iOS17AppleMusic, haptic: .success)
    }

    private func requestLongPressRoute(_ destination: CLLocationCoordinate2D) {
        mapMove.cancel()
        longPressRoute.request(destination: destination, enabled: longPressToCreateRoute,
            confirm: confirmLongPressRoute, autoStart: autoStartLongPressRoute,
            spoofedStart: locationSession.isActive ? locationSession.current?.coordinate : nil,
            routeRunning: routeSimulator.isSimulating,
            lookup: { completion in
                longPressLocation.request(requirePrecise: true, completion: completion)
                return { longPressLocation.cancel() }
            }, create: { endpoints in
                guard !routeSimulator.isSimulating else { return }
                joystickActive = false
                routeDraft.prepareFromMap(start: RoutePlace(name: endpoints.startName, coordinate: endpoints.start),
                    destination: RoutePlace(name: "Map pin", coordinate: endpoints.destination),
                    autoStart: endpoints.autoStart)
                showRouteSheet = true
            })
    }
    
}
