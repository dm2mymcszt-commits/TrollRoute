import Foundation

enum LocationAuthorization: CaseIterable {
    case notDetermined, restricted, denied, authorizedAlways, authorizedWhenInUse, unknown
}
enum LocationAccuracy: CaseIterable {
    case fullAccuracy, reducedAccuracy, unknown
}

/// Permission facts, independent of spoofing authority or route motion.
struct LocationAccessStatus {
    let registration: String?
    let authorization: LocationAuthorization
    let accuracy: LocationAccuracy
    let servicesEnabled: Bool

    var registrationText: String {
        switch registration {
        case "System": return "System"
        case "User": return "User"
        default: return "Unknown"
        }
    }
    // Neither registration is a location-permission error.
    var registrationNeedsCorrection: Bool { false }
    var authorized: Bool {
        servicesEnabled && (authorization == .authorizedAlways || authorization == .authorizedWhenInUse)
    }
    var accessText: String {
        guard servicesEnabled else { return "Location Services off" }
        switch authorization {
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Never"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While Using the App"
        case .unknown: return "Unknown"
        }
    }
    var precise: Bool { authorized && accuracy == .fullAccuracy }
    var accuracyText: String {
        guard authorized else { return "Unavailable" }
        switch accuracy {
        case .fullAccuracy: return "On"
        case .reducedAccuracy: return "Off"
        case .unknown: return "Unknown"
        }
    }
    /// Existing foreground-started updates also continue during route pauses.
    func canStartUpdates(inForeground: Bool) -> Bool {
        authorized && (inForeground || authorization == .authorizedAlways)
    }
}

#if canImport(UIKit)
import UIKit
import SwiftUI
import CoreLocation

extension LocationAccessStatus {
    init(registration: String?, coreAuthorization: CLAuthorizationStatus,
         coreAccuracy: CLAccuracyAuthorization, servicesEnabled: Bool) {
        let authorization: LocationAuthorization
        switch coreAuthorization {
        case .notDetermined: authorization = .notDetermined
        case .restricted: authorization = .restricted
        case .denied: authorization = .denied
        case .authorizedAlways: authorization = .authorizedAlways
        case .authorizedWhenInUse: authorization = .authorizedWhenInUse
        @unknown default: authorization = .unknown
        }
        let accuracy: LocationAccuracy
        switch coreAccuracy {
        case .fullAccuracy: accuracy = .fullAccuracy
        case .reducedAccuracy: accuracy = .reducedAccuracy
        @unknown default: accuracy = .unknown
        }
        self.init(registration: registration, authorization: authorization,
                  accuracy: accuracy, servicesEnabled: servicesEnabled)
    }
}

final class LocationAccessController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: LocationAccessStatus
    @Published private(set) var canOpenTrollStore = false
    @Published private(set) var message: String?
    private let manager: CLLocationManager?
    private static let trollStoreURL = URL(string: "apple-magnifier://")!
    static let precisePurpose = "RouteStart"

    init(preview: LocationAccessStatus? = nil) {
        status = preview ?? LocationAccessStatus(registration: nil, authorization: .notDetermined,
                                                accuracy: .reducedAccuracy, servicesEnabled: true)
        manager = preview == nil ? CLLocationManager() : nil
        super.init()
        manager?.delegate = self
        refresh()
    }
    func refresh() {
        guard let manager = manager else { return }
        status = LocationAccessStatus(registration: Self.registration(),
            coreAuthorization: manager.authorizationStatus, coreAccuracy: manager.accuracyAuthorization,
            servicesEnabled: CLLocationManager.locationServicesEnabled())
        canOpenTrollStore = Self.proxy("com.opa334.TrollStore") != nil
            && UIApplication.shared.canOpenURL(Self.trollStoreURL)
    }
    func requestAccess() {
        guard status.servicesEnabled, status.authorization == .notDetermined else { return }
        manager?.requestWhenInUseAuthorization()
    }
    func requestPrecise() {
        guard status.authorized, !status.precise else { return }
        message = nil
        manager?.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.precisePurpose) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.refresh()
                if !self.status.precise {
                    self.message = error == nil
                        ? "Precise Location is still off. You can enable it in iOS Settings, or choose a point on the map."
                        : "Couldn't request Precise Location. Enable it in iOS Settings, or choose a point on the map."
                }
            }
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { refresh() }
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
    func openTrollStore() {
        guard canOpenTrollStore,
              let type = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let workspace = type.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject else { return }
        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: selector) else { return }
        typealias Open = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let open = unsafeBitCast(workspace.method(for: selector), to: Open.self)
        if !open(workspace, selector, "com.opa334.TrollStore") {
            message = "Couldn't open TrollStore. Open it from your Home Screen and follow the instructions above."
        }
    }
    private static func proxy(_ identifier: String) -> NSObject? {
        guard let type = NSClassFromString("LSApplicationProxy") as? NSObject.Type,
              type.responds(to: NSSelectorFromString("applicationProxyForIdentifier:")) else { return nil }
        return type.perform(NSSelectorFromString("applicationProxyForIdentifier:"), with: identifier)?.takeUnretainedValue() as? NSObject
    }
    private static func registration() -> String? {
        guard let identifier = Bundle.main.bundleIdentifier, let proxy = proxy(identifier),
              proxy.responds(to: NSSelectorFromString("applicationType")) else { return nil }
        return proxy.perform(NSSelectorFromString("applicationType"))?.takeUnretainedValue() as? String
    }
}

struct LocationAccessOverview: View {
    @StateObject private var access: LocationAccessController
    @State private var detail: Detail?
    private enum Detail: String, Identifiable {
        case registration = "TrollStore registration", location = "Location access", accuracy = "Precise Location"
        var id: String { rawValue }
    }
    init(preview: LocationAccessStatus? = nil) {
        _access = StateObject(wrappedValue: LocationAccessController(preview: preview))
    }
    var body: some View {
        Section {
            row(.registration, value: access.status.registrationText, symbol: "info.circle", color: .secondary)
            row(.location, value: access.status.accessText,
                symbol: access.status.authorized ? "checkmark.circle" : "exclamationmark.circle",
                color: access.status.authorized ? .green : .orange)
            row(.accuracy, value: access.status.accuracyText,
                symbol: access.status.precise ? "checkmark.circle" : "exclamationmark.circle",
                color: access.status.precise ? .green : .orange)
        } header: { Text("Location access") } footer: {
            Text("While Using the App supports Current Location and routes started in TrollRoute, including continued background playback. Precise Location is recommended for an accurate start point.")
        }
        .onAppear { access.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in access.refresh() }
        .sheet(item: $detail) { choice in
            NavigationView {
                Form {
                    Section {
                        Text(explanation(choice))
                        if choice == .registration {
                            if access.canOpenTrollStore { Button("Open TrollStore") { access.openTrollStore() } }
                        } else {
                            if choice == .location && access.status.servicesEnabled && access.status.authorization == .notDetermined {
                                Button("Allow location access") { access.requestAccess() }
                            }
                            if choice == .accuracy && access.status.authorized && !access.status.precise {
                                Button("Request Precise Location") { access.requestPrecise() }
                            }
                            if access.status.authorization != .restricted {
                                Button("Open iOS Settings") { access.openSettings() }
                            }
                            Text("If TrollRoute's page is missing, see TrollStore registration in the status overview.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if let message = access.message { Text(message).foregroundColor(.secondary) }
                    }
                }
                .navigationTitle(choice.rawValue).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } } }
            }
        }
    }
    private func row(_ detail: Detail, value: String, symbol: String, color: Color) -> some View {
        Button { self.detail = detail } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(detail.rawValue).foregroundColor(.primary)
                    Text(value).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: symbol).foregroundColor(color)
            }
        }.accessibilityIdentifier("access-" + detail.id)
    }
    private func explanation(_ detail: Detail) -> String {
        switch detail {
        case .registration:
            return "Current registration: \(access.status.registrationText). System registration is normal for TrollStore apps. Only if TrollRoute's page is missing in iOS Settings: open TrollStore → Apps → TrollRoute → Switch to \"User\" Registration. Adjust permissions, then switch back to \"System\" Registration so TrollRoute remains launchable after a respring. Registration is never changed automatically."
        case .location:
            if !access.status.servicesEnabled { return "Location Services is off. Turn it on in iOS Settings → Privacy & Security → Location Services, then allow TrollRoute to use your location." }
            if access.status.authorization == .restricted { return "Location access is restricted by Screen Time or device management. Check those restrictions or ask the device administrator. You can still choose a route start on the map." }
            return "Current access: \(access.status.accessText). TrollRoute uses location for Current Location and to keep a route active in the background. While Using the App is sufficient when the route starts with TrollRoute open; updates stay active while paused. Always is not required for that flow. Without access, Current Location and reliable background playback are unavailable; you can still select places manually."
        case .accuracy:
            return "Precise Location: \(access.status.accuracyText). Approximate location can put a route start far from your actual position. Request precise access, or enable Precise Location under TrollRoute in iOS Settings → Location. You can also choose the exact start on the map. TrollRoute cannot change this privacy setting for you."
        }
    }
}

/// Explain the limitation before starting from manually chosen endpoints,
/// where Current Location would not otherwise have requested permission.
struct RouteLocationAccessNotice: View {
    @StateObject private var access = LocationAccessController()
    @State private var showAccess = false
    var body: some View {
        Group {
            if !access.status.authorized {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allow location access for reliable background route playback. Without it, keep TrollRoute open. You can still choose places manually.")
                        .font(.caption).foregroundColor(.secondary)
                    Button("Review location access") { showAccess = true }
                }.padding(.horizontal)
            }
        }
        .onAppear { access.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in access.refresh() }
        .sheet(isPresented: $showAccess) {
            NavigationView {
                Form { LocationAccessOverview() }
                    .navigationTitle("Location access").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAccess = false } } }
            }
        }
    }
}
#endif
