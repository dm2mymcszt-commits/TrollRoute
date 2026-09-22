import SwiftUI

struct SettingsView: View {
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

    var body: some View {
        NavigationView {
            Form {
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
                    Toggle("Tap map to set location", isOn: $tapMapToSetLocation)
                    if tapMapToSetLocation {
                        Toggle("Ask before moving", isOn: $askBeforeMoving)
                    }
                    Toggle("Long press to create route", isOn: $longPressToCreateRoute)
                    if longPressToCreateRoute {
                        Toggle("Confirm before creating route from long press", isOn: $confirmLongPressRoute)
                        Toggle("Automatically start route after long press", isOn: $autoStartLongPressRoute)
                    }
                }
                Section {
                    Toggle("Confirm before stopping location spoofing", isOn: $confirmBeforeStoppingSpoofing)
                } header: { Text("Location") }
                LocationAccessOverview()
                Section("Default action when a route finishes") {
                    Picker("Action", selection: Binding(get: { finishSettings.action }, set: { action in
                        if action == .goToPlace && finishSettings.destination == nil {
                            selectGoAfterPicking = true
                            showFinishPlacePicker = true
                        } else { finishSettings.action = action }
                    })) {
                        ForEach(RouteFinishAction.allCases) { action in Text(action.title).tag(action) }
                    }
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
                    Text("The starting choice for each new route. Route-specific choices do not change this default. Notifications are requested when you first start a route.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("Default action when stopping a route") {
                    Picker("Action", selection: $routeStopDefault) {
                        ForEach(RouteStopAction.defaults) { action in Text(action.title).tag(action.rawValue) }
                    }
                    Text("Preselects a choice only. Stopping a route always asks what should happen to your location. If Return to previous spoofed location is unavailable, Stay at current location is selected instead.")
                        .font(.caption).foregroundColor(.secondary)
                }
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
                    Text("[Data: Apple Maps, \u{00A9} OpenStreetMap contributors, national address and elevation services](https://github.com/dm2mymcszt-commits/TrollRoute/blob/experiment/route-motion/THIRD-PARTY-NOTICES.md)")
                        .font(.caption).foregroundColor(.secondary)
                }
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
}
