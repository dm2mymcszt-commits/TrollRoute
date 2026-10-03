import SwiftUI

struct RouteFinishControls: View {
    @Binding var configuration: RouteFinishConfiguration
    let active: Bool
    var flying = false
    @StateObject private var recents = RouteRecentPlaces()
    @State private var showPlace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When this route finishes").font(.headline)
            Picker("Action", selection: Binding(get: { configuration.action }, set: { action in
                if action == .goToPlace && configuration.destination == nil { showPlace = true }
                else { configuration.action = action }
            })) {
                ForEach(RouteFinishAction.allCases) { action in Text(action.title(flying: flying)).tag(action) }
            }.pickerStyle(.menu).accessibilityIdentifier("route-finish-action")
            if configuration.action == .goToPlace {
                if let place = configuration.destination {
                    Text(place.name).font(.subheadline)
                    if !place.address.isEmpty { Text(place.address).font(.caption).foregroundColor(.secondary) }
                }
                Button("Change place for this route") { showPlace = true }
            }
            Text(active
                 ? "Applies when the current leg ends. Your Settings default stays unchanged."
                 : "For this route only. Your Settings default stays unchanged.")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showPlace) {
            RouteLocationPicker(title: "After this route", region: nil,
                selectedCoordinate: configuration.destination.map { CoordTransform.wgs84ToGcj02($0.coordinate) },
                recents: recents) { place in
                    // Commit action and place together; cancelling never installs an invalid action.
                    configuration = RouteFinishConfiguration(action: .goToPlace,
                        destination: RouteFinishDestination(name: place.name, address: place.address,
                            coordinate: CoordTransform.gcj02ToWgs84(place.coordinate)))
                    recents.remember(place)
                }
        }
    }
}
