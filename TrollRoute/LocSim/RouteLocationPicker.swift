import SwiftUI
import MapKit

struct RouteLocationPicker: View {
    let title: String
    let region: MKCoordinateRegion?
    let selectedCoordinate: CLLocationCoordinate2D?
    @ObservedObject var recents: RouteRecentPlaces
    var useCurrentLocation: (() -> Void)?
    var initialQuery: String = ""
    let select: (RoutePlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = RoutePlaceSearch()
    @State private var showMap = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var favoriteChanges = SharedPlaceChannel()
    @State private var favoriteError: String?
    @State private var favorites: [RoutePlace] = []
    @State private var favoriteToSave: RoutePlace?

    private var matchingFavorites: [RoutePlace] {
        RouteFavoritePlaces.matching(favorites, query: search.query)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    if let useCurrentLocation = useCurrentLocation {
                        Button {
                            useCurrentLocation()
                            dismiss()
                        } label: { Label("Use Current Location", systemImage: "location.fill") }
                    }
                    Button {
                        search.cancel()
                        showMap = true
                    } label: { Label("Choose on Map", systemImage: "map") }
                }
                if search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !matchingFavorites.isEmpty {
                    Section("Favorites") {
                        if let error = favoriteError { Text(error).foregroundColor(.secondary) }
                        else if favorites.isEmpty {
                            Text("Save places in Favorites to choose them here.").foregroundColor(.secondary)
                        }
                        ForEach(matchingFavorites) { place in
                            Button { choose(place) } label: {
                                placeRow(place.name, subtitle: place.address, icon: "star.fill")
                            }
                        }
                    }
                }
                if search.isSearching { ProgressView("Searching…") }
                if let message = search.message { Text(message).foregroundColor(.secondary) }
                if !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { search.searchAddress() } label: {
                        Label("Search full address", systemImage: "magnifyingglass")
                    }
                    .disabled(search.isSearching)
                }
                if search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Recent Places") {
                        if recents.places.isEmpty {
                            Text("Places you choose here will appear here next time.")
                                .foregroundColor(.secondary)
                        }
                        ForEach(recents.places) { place in
                            HStack {
                                Button { choose(place) } label: {
                                    placeRow(place.name, subtitle: place.address, icon: "clock")
                                }
                                .buttonStyle(.borderless)
                                Button { recents.remove(place) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(place.name) from recent places")
                            }
                        }
                    }
                } else {
                    ForEach(search.suggestions, id: \.self) { suggestion in
                      HStack {
                        Button {
                            search.resolve(suggestion, selection: choose)
                        } label: {
                            placeRow(suggestion.title, subtitle: suggestion.subtitle, icon: "mappin.circle")
                        }
                        .buttonStyle(.borderless)
                        Button {
                            search.resolve(suggestion) { favoriteToSave = $0 }
                        } label: { Image(systemName: "star") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Save \(suggestion.title) as favorite")
                      }
                    }
                    ForEach(search.results) { place in
                      HStack {
                        Button { choose(place) } label: {
                            placeRow(place.name, subtitle: [place.address, place.isApproximate ? "Approximate" : nil].compactMap { $0 }.joined(separator: "\n"), icon: "mappin.circle")
                        }
                        .buttonStyle(.borderless)
                        Button { favoriteToSave = place } label: { Image(systemName: "star") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Save \(place.name) as favorite")
                      }
                    }
                }
            }
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search address or place")
            .onSubmit(of: .search) { search.searchAddress() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showMap, onDismiss: reloadFavorites) {
                RouteMapPicker(title: title, region: region, selectedCoordinate: selectedCoordinate,
                               select: choose)
            }
            .sheet(item: $favoriteToSave) { place in
                FavoritePlaceEditor(place: place, didSave: reloadFavorites)
            }
        }
        .onAppear {
            reloadFavorites()
            search.region = region
            if search.query.isEmpty && !initialQuery.isEmpty { search.query = initialQuery }
        }
        .onChange(of: favoriteChanges.revision) { _ in reloadFavorites() }
        .onChange(of: scenePhase) { phase in if phase == .active { reloadFavorites() } }
        .onDisappear { search.cancel() }
    }

    private func reloadFavorites() {
        do {
            favorites = RouteFavoritePlaces.places(from: try BookMarkRetrieve())
            favoriteError = nil
        } catch { favoriteError = error.localizedDescription }
    }

    private func choose(_ place: RoutePlace) {
        search.cancel()
        select(place)
        dismiss()
    }

    private func placeRow(_ name: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).foregroundColor(.primary)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundColor(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct RouteMapPicker: View {
    let title: String
    let region: MKCoordinateRegion?
    let selectedCoordinate: CLLocationCoordinate2D?
    let select: (RoutePlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var point: EquatableCoordinate?
    @State private var favoriteToSave: RoutePlace?

    private var selectedPlace: RoutePlace? {
        point.map { RoutePlace(name: "Map pin", address: String(format: "%.5f, %.5f",
            $0.coordinate.latitude, $0.coordinate.longitude), coordinate: $0.coordinate) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text("Move and zoom the map, then tap your \(title.lowercased()).")
                    .font(.subheadline).foregroundColor(.secondary).padding()
                RouteSelectionMap(region: region, selectedCoordinate: selectedCoordinate, point: $point)
                VStack(spacing: 10) {
                    if let point = point {
                        Text(String(format: "%.5f, %.5f", point.coordinate.latitude, point.coordinate.longitude))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Button {
                        guard let place = selectedPlace else { return }
                        select(place)
                        dismiss()
                    } label: {
                        Text("Use as \(title)").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(point == nil)
                    Button { favoriteToSave = selectedPlace } label: {
                        Label("Save as favorite", systemImage: "star")
                    }.disabled(point == nil)
                }
                .padding()
            }
            .navigationTitle("Choose on Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $favoriteToSave) { place in FavoritePlaceEditor(place: place) }
        }
    }
}

// This map only selects a coordinate. It never starts or changes location simulation.
private struct RouteSelectionMap: UIViewRepresentable {
    @AppStorage("mapStyle", store: SharedPreferences.defaults) private var mapStyle = "standard"
    let region: MKCoordinateRegion?
    let selectedCoordinate: CLLocationCoordinate2D?
    @Binding var point: EquatableCoordinate?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = mapStyle == "hybrid" ? .hybrid : .standard
        map.showsUserLocation = true
        if let coordinate = selectedCoordinate {
            map.setRegion(MKCoordinateRegion(center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)), animated: false)
        } else if let region = region {
            map.setRegion(region, animated: false)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if let point = point {
            if let pin = context.coordinator.pin {
                pin.coordinate = point.coordinate
            } else {
                let pin = MKPointAnnotation()
                pin.coordinate = point.coordinate
                pin.title = "Selected point"
                map.addAnnotation(pin)
                context.coordinator.pin = pin
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        var parent: RouteSelectionMap
        var pin: MKPointAnnotation?
        init(_ parent: RouteSelectionMap) { self.parent = parent }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MKMapView else { return }
            parent.point = EquatableCoordinate(coordinate: map.convert(gesture.location(in: map), toCoordinateFrom: map))
        }
    }
}
