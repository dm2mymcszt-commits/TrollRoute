import SwiftUI
import MapKit

let qaRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TROLLROUTE_QA_ROOT"]!)
let qaFavorites = FavoritesStore(url: qaRoot.appendingPathComponent("favorites.json"))
enum QAFixture { static let shared = EngineFixture(realtime: true) }

struct EquatableCoordinate: Equatable {
    let coordinate: CLLocationCoordinate2D
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

// Replace only decorative toasts/haptics; failure dialogs and all actions remain.
enum AlertKitAPI {
    enum Icon { case done }
    enum Style { case iOS17AppleMusic }
    enum Haptic { case success }
    static func present(title: String, icon: Icon, style: Style, haptic: Haptic) {}
}
func successVibrate() {}
extension UIApplication {
    func alert(body: String) {
        let alert = UIAlertController(title: "TrollRoute", message: body, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first?
            .rootViewController?.present(alert, animated: true)
    }
}

@main struct ShareLifecycleApp: App {
    init() {
        SharedPreferences.defaults.set(true, forKey: "mapButtonLabels")
        SharedPreferences.defaults.set(false, forKey: "tapMapToSetLocation")
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--share") {
                    SharePlaceView(initialPlace: sharedPlace, load: { [] }, done: {}, openContainingApp: { _ in
                        try! Data("opened".utf8).write(to: qaRoot.appendingPathComponent("opened"))
                        return true
                    })
                } else {
                    LocSimView()
                }
            }.tint(.indigo).preferredColorScheme(.dark)
        }
    }
    private var sharedPlace: RoutePlace {
        var place = RoutePlace(name: "Shared landmark", address: "Saved address",
            coordinate: CLLocationCoordinate2D(latitude: 44.8378, longitude: -0.5792))
        place.sharedSource = .googleMaps
        return place
    }
}
