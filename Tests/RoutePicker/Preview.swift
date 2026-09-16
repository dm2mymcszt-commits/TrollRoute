import SwiftUI
import MapKit

// Separate simulator-only app using the production picker; never bundled in TrollRoute.
struct EquatableCoordinate: Equatable {
    let coordinate: CLLocationCoordinate2D
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

@main struct RoutePickerPreview: App {
    private var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--screen"), args.indices.contains(index + 1) else { return "Destination" }
        return args[index + 1]
    }
    private let places: RouteRecentPlaces = {
        _ = BookMarkSave(lat: 44.817059, long: -0.585746, name: "Café préféré")
        _ = BookMarkSave(lat: 48.8584, long: 2.2945, name: "Tour Eiffel")
        let defaults = UserDefaults(suiteName: "RoutePickerPreview")!
        defaults.removePersistentDomain(forName: "RoutePickerPreview")
        let places = RouteRecentPlaces(defaults: defaults)
        places.remember(RoutePlace(name: "Gare de Lyon", address: "Place Louis-Armand, Paris",
                                  coordinate: CLLocationCoordinate2D(latitude: 48.8449, longitude: 2.3735)))
        places.remember(RoutePlace(name: "Jardin du Luxembourg", address: "Paris",
                                  coordinate: CLLocationCoordinate2D(latitude: 48.8462, longitude: 2.3372)))
        return places
    }()
    var body: some Scene {
        WindowGroup {
            Group {
            if screen == "Share" {
                SharePlaceView(initialPlace: RoutePlace(name: "Shared place", address: "44.81706, -0.58575", coordinate: CLLocationCoordinate2D(latitude: 44.817059, longitude: -0.585746)), load: { [] }, done: {})
            } else if screen == "Incoming" {
                IncomingPlaceView(request: SharedPlaceRequest(place: RoutePlace(name: "Shared place", address: "44.81706, -0.58575", coordinate: CLLocationCoordinate2D(latitude: 44.817059, longitude: -0.585746)), action: .go), routeRunning: true, accept: {}, cancel: {})
            } else {
            RouteLocationPicker(title: screen == "Filtered" ? "Search" : screen, region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)),
                selectedCoordinate: nil, recents: places, useCurrentLocation: {},
                initialQuery: screen == "Filtered" ? "cafe" : (screen == "Pasted" ? "44.817059, -0.585746" : ""), select: { _ in })
            }
            }.tint(.indigo).preferredColorScheme(.dark)
        }
    }
}
