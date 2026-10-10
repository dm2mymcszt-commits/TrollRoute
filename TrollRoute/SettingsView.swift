import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var history: RouteHistoryStore = .shared
    var replayHistory: ((RouteHistoryEntry) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mapAppearance", store: SharedPreferences.defaults) private var mapAppearance = "system"
    @AppStorage("mapStyle", store: SharedPreferences.defaults) private var mapStyle = "standard"
    @AppStorage("mapButtonLabels", store: SharedPreferences.defaults) private var mapButtonLabels = true
    @AppStorage("mapHaptics", store: SharedPreferences.defaults) private var mapHaptics = true
    @AppStorage("tapMapToSetLocation", store: SharedPreferences.defaults) private var tapMapToSetLocation = false
    @AppStorage("askBeforeMoving", store: SharedPreferences.defaults) private var askBeforeMoving = true
    @AppStorage("confirmBeforeStoppingSpoofing", store: SharedPreferences.defaults) private var confirmBeforeStoppingSpoofing = true
    @AppStorage("longPressToCreateRoute", store: SharedPreferences.defaults) private var longPressToCreateRoute = true
    @AppStorage("confirmLongPressRoute", store: SharedPreferences.defaults) private var confirmLongPressRoute = false
    @AppStorage("autoStartLongPressRoute", store: SharedPreferences.defaults) private var autoStartLongPressRoute = false
    @ObservedObject private var finishSettings = RouteFinishSettings.shared
    @StateObject private var recentPlaces = RouteRecentPlaces()
    @State private var showFinishPlacePicker = false
    @State private var selectGoAfterPicking = false
    @AppStorage("routeStopDefault", store: SharedPreferences.defaults) private var routeStopDefault = RouteStopAction.previous.rawValue
    @AppStorage(RouteNotificationPreferences.finishedKey, store: SharedPreferences.defaults) private var routeFinishedNotifications = true
    @AppStorage(RouteNotificationPreferences.timeSensitiveKey, store: SharedPreferences.defaults) private var routeTimeSensitiveNotifications = false

    var body: some View {
        NavigationView {
            Form {
                NavigationLink { Form { mapOptions }.navigationTitle("Map") } label: { Label("Map", systemImage: "map") }
                NavigationLink { Form { gestureOptions }.navigationTitle("Gestures") } label: { Label("Gestures", systemImage: "hand.tap") }
                NavigationLink { Form { routeOptions }.navigationTitle("Routes") } label: { Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                NavigationLink { Form { safetyOptions }.navigationTitle("Safety") } label: { Label("Safety", systemImage: "checkmark.shield") }
                NavigationLink { Form { notificationOptions; RouteActivitySettings() }.navigationTitle("Notifications") } label: {
                    Label("Notifications and Live Activity", systemImage: "bell")
                }
                NavigationLink { Form { LocationAccessOverview() }.navigationTitle("Access") } label: { Label("Access", systemImage: "location.circle") }
                NavigationLink { Form { KeeperDiagnosticsSection(model: KeeperStatusModel.shared) }.navigationTitle("Diagnostics") } label: { Label("Diagnostics", systemImage: "waveform.path.ecg") }
                NavigationLink { Form { aboutOptions }.navigationTitle("About") } label: { Label("About", systemImage: "info.circle") }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showFinishPlacePicker) {
                RouteLocationPicker(title: "After the route", region: nil,
                    selectedCoordinate: finishSettings.destination.map { CoordTransform.wgs84ToGcj02($0.coordinate) },
                    recents: recentPlaces, select: { place in
                        finishSettings.destination = RouteFinishDestination(name: place.name, address: place.address,
                            coordinate: CoordTransform.gcj02ToWgs84(place.coordinate))
                        recentPlaces.remember(place)
                        if selectGoAfterPicking { finishSettings.action = .goToPlace }
                    })
            }
        }
    }

    private var mapOptions: some View {
        Section("Map") {
            Picker("Appearance", selection: $mapAppearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Picker("Map style", selection: $mapStyle) {
                Text("Standard").tag("standard")
                Text("Satellite").tag("hybrid")
            }
            Toggle("Show button labels", isOn: $mapButtonLabels)
            Toggle("Button haptics", isOn: $mapHaptics)
        }
    }
    private var gestureOptions: some View {
        Group {
            Section("Map taps") {
                Toggle("Tap map to set location", isOn: $tapMapToSetLocation)
                if tapMapToSetLocation { Toggle("Ask before moving", isOn: $askBeforeMoving) }
            }
            Section("Long press") {
                Toggle("Long press to create route", isOn: $longPressToCreateRoute)
                if longPressToCreateRoute {
                    Toggle("Confirm before creating route from long press", isOn: $confirmLongPressRoute)
                    Toggle("Automatically start route after long press", isOn: $autoStartLongPressRoute)
                }
            }
        }
    }
    private var routeOptions: some View {
        Group {
            Section("Default action when a route finishes") {
                Menu {
                    Picker("Action", selection: Binding(get: { finishSettings.action }, set: { action in
                        if action == .goToPlace && finishSettings.destination == nil {
                            selectGoAfterPicking = true
                            showFinishPlacePicker = true
                        } else { finishSettings.action = action }
                    })) {
                        ForEach(RouteFinishAction.allCases) { action in Text(action.title).tag(action) }
                    }
                } label: { actionLabel(finishSettings.action.title) }
                .accessibilityIdentifier("settings-finish-action")
                if finishSettings.action == .goToPlace {
                    Button {
                        selectGoAfterPicking = false
                        showFinishPlacePicker = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(finishSettings.destination?.name ?? "Choose a place")
                            if let destination = finishSettings.destination {
                                Text(destination.address.isEmpty ? String(format: "%.5f, %.5f", destination.latitude, destination.longitude) : destination.address)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Text("Starting choice for new routes. Each trip can use a different action.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Default action when stopping a route") {
                Menu {
                    Picker("Action", selection: $routeStopDefault) {
                        ForEach(RouteStopAction.defaults) { action in Text(action.title).tag(action.rawValue) }
                    }
                } label: { actionLabel((RouteStopAction(rawValue: routeStopDefault) ?? .previous).title) }
                .accessibilityIdentifier("settings-stop-action")
                DisclosureGroup("About stopping routes") {
                    Text("Preselects a choice only. Stopping a route always asks what should happen to your location. If Return to previous spoofed location is unavailable, Stay at current location is selected instead.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Section {
                NavigationLink("History") { RouteHistoryView(store: history, replay: replayHistory) }
            }
        }
    }
    private func actionLabel(_ title: String) -> some View {
        HStack {
            Text(title).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down").font(.caption)
        }
    }
    @ViewBuilder private var safetyOptions: some View {
        KeeperSettingsSection(model: KeeperStatusModel.shared)
        Section("Location spoofing") {
            Toggle("Confirm before stopping location spoofing", isOn: $confirmBeforeStoppingSpoofing)
        }
    }
    private var notificationOptions: some View {
        Section("Notifications") {
            Toggle("Route finished", isOn: $routeFinishedNotifications)
            Toggle("Time Sensitive", isOn: $routeTimeSensitiveNotifications).disabled(!routeFinishedNotifications)
            DisclosureGroup("About notifications") {
                Text("Permission is requested when you start a route with notifications enabled. Repeating routes notify only on the first arrival. Time Sensitive can notify during Focus or Do Not Disturb when allowed by iOS. If alerts are blocked, check TrollRoute's notification settings and Allow Time Sensitive Notifications in your Focus settings.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }
    private var aboutOptions: some View {
        Section("About") {
            HStack {
                Text("TrollRoute")
                Spacer()
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .foregroundColor(.secondary)
            }
            Link("Source code", destination: URL(string: "https://github.com/dm2mymcszt-commits/TrollRoute")!)
            Text("Based on Andromeda by son3ra1n and Geranium by c22dev. GPL-3.0.")
                .font(.caption).foregroundColor(.secondary)
            Text("[Data: Apple Maps, \u{00A9} OpenStreetMap contributors, OurAirports, national address and elevation services](https://github.com/dm2mymcszt-commits/TrollRoute/blob/experiment/route-motion/THIRD-PARTY-NOTICES.md)")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}
