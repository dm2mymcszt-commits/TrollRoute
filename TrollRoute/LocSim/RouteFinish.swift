import Foundation
import CoreLocation
import Combine

enum RouteFinishAction: String, CaseIterable, Identifiable {
    case stay, goToPlace, stop, loop, returnOnce, backAndForth
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stay: return "Stay at destination"
        case .goToPlace: return "Go to a place"
        case .stop: return "Stop location simulation"
        case .loop: return "Restart the route (loop)"
        case .returnOnce: return "Drive back to start"
        case .backAndForth: return "Back and forth (repeat)"
        }
    }
}

struct RouteFinishDestination: Codable, Equatable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(name: String, address: String, coordinate: CLLocationCoordinate2D) {
        self.name = name; self.address = address
        latitude = coordinate.latitude; longitude = coordinate.longitude
    }
}

final class RouteFinishSettings: ObservableObject {
    static let shared = RouteFinishSettings()
    private let defaults: UserDefaults
    @Published var action: RouteFinishAction { didSet { defaults.set(action.rawValue, forKey: "routeFinishAction") } }
    @Published var destination: RouteFinishDestination? {
        didSet { defaults.set(try? JSONEncoder().encode(destination), forKey: "routeFinishDestination") }
    }
    init(defaults: UserDefaults = SharedPreferences.defaults) {
        self.defaults = defaults
        action = RouteFinishAction(rawValue: defaults.string(forKey: "routeFinishAction") ?? "") ?? .stay
        let place = defaults.data(forKey: "routeFinishDestination").flatMap {
            try? JSONDecoder().decode(RouteFinishDestination.self, from: $0)
        }
        destination = place.flatMap { CLLocationCoordinate2DIsValid($0.coordinate) ? $0 : nil }
    }
}

// A value copy for one prepared/active trip. Editing it never writes defaults.
struct RouteFinishConfiguration: Equatable {
    var action: RouteFinishAction
    var destination: RouteFinishDestination?
    init(action: RouteFinishAction = .stay, destination: RouteFinishDestination? = nil) {
        self.action = action
        self.destination = destination
    }
    init(defaults: RouteFinishSettings) {
        action = defaults.action
        destination = defaults.destination
    }
    var isValid: Bool {
        action != .goToPlace || destination.map { CLLocationCoordinate2DIsValid($0.coordinate) } == true
    }
}

enum RouteFinishEffect: Equatable { case hold, goToPlace, stop, restart, reverse }

// Used by both normal arrival and a seek to the end. Only a new route resets
// notification counts; a new leg preserves the current trip's settings.
struct RouteFinishState {
    private(set) var action: RouteFinishAction
    private(set) var completedLegs = 0
    private(set) var returning = false
    var legName: String {
        switch action {
        case .loop: return "Lap \(completedLegs + 1)"
        case .returnOnce: return returning ? "Returning to start" : "Route in progress"
        case .backAndForth: return "Leg \(completedLegs + 1) · \(returning ? "Returning to start" : "Going to destination")"
        default: return returning ? "Returning to start" : "Route in progress"
        }
    }
    mutating func changeAction(_ action: RouteFinishAction) {
        // Keep current-leg orientation and trip notification history.
        self.action = action
    }
    mutating func skipRepeatedLegs(_ count: Int) {
        guard count > 0, action == .loop || action == .backAndForth else { return }
        completedLegs += count
        if action == .backAndForth && count % 2 == 1 { returning.toggle() }
    }
    mutating func arrive() -> (effect: RouteFinishEffect, notification: String?) {
        completedLegs += 1
        switch action {
        case .stay: return (.hold, returning ? "Staying at the start" : "Staying at destination")
        case .goToPlace: return (.goToPlace, "Moving to your saved place")
        case .stop: return (.stop, "Restoring your real location")
        case .loop:
            returning = false
            return (.restart, completedLegs == 1 ? "Restarting the route" : nil)
        case .returnOnce:
            if !returning { returning = true; return (.reverse, "Returning to start") }
            return (.hold, "Staying at the start")
        case .backAndForth:
            returning.toggle()
            return (.reverse, completedLegs == 1 ? "Returning to start" : nil)
        }
    }
}

/// Read at delivery time so changing a preference also affects an active trip.
struct RouteNotificationPreferences {
    static let finishedKey = "routeFinishedNotifications"
    static let timeSensitiveKey = "routeTimeSensitiveNotifications"
    let defaults: UserDefaults
    init(defaults: UserDefaults = SharedPreferences.defaults) { self.defaults = defaults }
    var finished: Bool {
        get { defaults.object(forKey: Self.finishedKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.finishedKey) }
    }
    var timeSensitive: Bool {
        get { defaults.object(forKey: Self.timeSensitiveKey) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Self.timeSensitiveKey) }
    }
    enum Delivery: Equatable { case disabled, active, timeSensitive }
    var delivery: Delivery { !finished ? .disabled : (timeSensitive ? .timeSensitive : .active) }
}

#if os(iOS)
import UserNotifications

final class RouteNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RouteNotifications()
    private let center = UNUserNotificationCenter.current()
    private override init() {
        super.init()
        center.delegate = self
    }
    func requestPermissionIfNeeded() async {
        guard RouteNotificationPreferences().finished else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined && RouteNotificationPreferences().finished {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }
    func complete(_ message: String) {
        guard let content = Self.content(message, preferences: RouteNotificationPreferences()) else { return }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    static func content(_ message: String, preferences: RouteNotificationPreferences) -> UNMutableNotificationContent? {
        guard preferences.delivery != .disabled else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Route complete"
        content.body = message
        content.sound = .default
        content.interruptionLevel = preferences.delivery == .timeSensitive ? .timeSensitive : .active
        return content
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(RouteNotificationPreferences().finished ? [.banner, .list, .sound] : [])
    }
}
#endif
