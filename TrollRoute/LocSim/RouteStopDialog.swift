import SwiftUI

struct RouteStopDialog: View {
    let request: RouteStopRequest
    let cancel: () -> Void
    let confirm: (RouteStopAction, RouteFinishDestination?) -> Void
    let choosePlaceImmediately: Bool
    @State private var selection: RouteStopAction
    @State private var place: RouteFinishDestination?
    @State private var showPicker = false
    @StateObject private var recents = RouteRecentPlaces()

    init(request: RouteStopRequest, choosePlaceImmediately: Bool = false, cancel: @escaping () -> Void,
         confirm: @escaping (RouteStopAction, RouteFinishDestination?) -> Void) {
        self.request = request
        self.cancel = cancel
        self.confirm = confirm
        self.choosePlaceImmediately = choosePlaceImmediately
        _selection = State(initialValue: request.preselection)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    ForEach(request.choices) { action in
                        Button {
                            if action == .specific && place == nil { showPicker = true }
                            else { selection = action }
                        } label: {
                            HStack(spacing: 12) {
                                Text(action.title).foregroundColor(.primary)
                                Spacer(minLength: 8)
                                Image(systemName: selection == action ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(.accentColor)
                            }.padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("route-stop-" + action.rawValue)
                        .accessibilityValue(selection == action ? "Selected" : "Not selected")
                    }
                } header: { Text("What should happen to your location?") } footer: {
                    Text("The route keeps its current playback state until you confirm. Stay at current location uses the position captured when you pressed Stop.")
                }
                if selection == .specific, let place = place {
                    Section("Selected place") {
                        Button { showPicker = true } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(place.name)
                                if !place.address.isEmpty { Text(place.address).font(.caption) }
                            }
                        }
                    }
                }
                Section {
                    Button("Stop route") { confirm(selection, place) }
                        .accessibilityIdentifier("confirm-route-stop")
                        .disabled(selection == .specific && place == nil)
                }
            }
            .navigationTitle("Stop route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }
            .sheet(isPresented: $showPicker) {
                RouteLocationPicker(title: "After stopping", region: nil,
                    selectedCoordinate: place.map { CoordTransform.wgs84ToGcj02($0.coordinate) },
                    recents: recents) { picked in
                        place = RouteFinishDestination(name: picked.name, address: picked.address,
                            coordinate: CoordTransform.gcj02ToWgs84(picked.coordinate))
                        selection = .specific
                        recents.remember(picked)
                        if choosePlaceImmediately { confirm(.specific, place) }
                    }
            }
            .onAppear { if choosePlaceImmediately { showPicker = true } }
            .onChange(of: choosePlaceImmediately) { requested in
                if requested { showPicker = true }
            }
        }
    }
}

/// Attach to both the map and Navigation; only the visible owner presents it.
struct RouteStopPresentation: ViewModifier {
    @ObservedObject var simulator: RouteSimulator
    var enabled = true
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { enabled ? simulator.stopRequest : nil }, set: { value in
            if value == nil, let request = simulator.stopRequest { simulator.cancelRouteStop(request.id) }
        })) { request in
            RouteStopDialog(request: request,
                choosePlaceImmediately: simulator.activityStopPickerID == request.id,
                cancel: { simulator.cancelRouteStop(request.id) },
                confirm: { simulator.confirmRouteStop(request.id, action: $0, place: $1) })
        }
    }
}
