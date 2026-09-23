import ActivityKit
import Combine
import UIKit
import SwiftUI

@MainActor
final class RouteActivityPreferences: ObservableObject {
    static let shared = RouteActivityPreferences()
    private let preference = RouteActivityPreference(defaults: SharedPreferences.defaults)
    @Published var enabled: Bool {
        didSet { preference.enabled = enabled }
    }
    @Published private(set) var availability: RouteActivityAvailability = .oldSystem
    @Published var message: String?
    private var activation: AnyCancellable?
    private var authorizationTask: Task<Void, Never>?

    private init() {
        enabled = RouteActivityPreference(defaults: SharedPreferences.defaults).enabled
        refresh()
        activation = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
        if #available(iOS 16.1, *) {
            authorizationTask = Task { [weak self] in
                for await _ in ActivityAuthorizationInfo().activityEnablementUpdates {
                    guard !Task.isCancelled else { return }
                    self?.refresh()
                }
            }
        }
    }

    func refresh() {
        if #available(iOS 16.1, *) {
            availability = .evaluate(systemSupportsActivities: true,
                activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled)
        } else { availability = .oldSystem }
    }
}

@MainActor
struct RouteActivitySettings: View {
    @ObservedObject private var preferences = RouteActivityPreferences.shared
    var body: some View {
        Section {
            Toggle("Live Activity", isOn: Binding(
                get: { preferences.availability == .supported && preferences.enabled },
                set: { preferences.enabled = $0 }))
                .disabled(preferences.availability != .supported)
                .accessibilityIdentifier("route-live-activity")
            if let reason = preferences.availability.reason { Text(reason).font(.caption).foregroundColor(.secondary) }
            if let message = preferences.message { Text(message).font(.caption).foregroundColor(.secondary) }
            Text("Shows the active route on the Lock Screen. On devices with a native Dynamic Island, it can also appear there. iOS may end a Live Activity after eight hours; the route keeps running.")
                .font(.caption).foregroundColor(.secondary)
            Link("DynamicCowTS / DynamicCow", destination: URL(string: "https://github.com/matteozappia/DynamicCowTS")!)
            Text("If your device has no native Dynamic Island, this separate, optional TrollStore app can modify its presentation. Check its own supported iOS versions. It is not included in TrollRoute.")
                .font(.caption).foregroundColor(.secondary)
        } header: { Text("Live Activity") }
    }
}

/// No ActivityKit symbols are stored on this iOS15-facing interface.
@MainActor
protocol RouteActivityPublishing: AnyObject {
    func sync(_ state: RouteActivityState?, enabled: Bool, foreground: Bool)
    func flush() async
}

@available(iOS 16.1, *)
@MainActor
final class RouteActivityController: RouteActivityPublishing {
    private var activity: Activity<RouteActivityAttributes>?
    private var policy = RouteActivityUpdatePolicy()
    private var desired: RouteActivityState?
    private var generation = 0
    private var worker: Task<Void, Never>?
    private var suppressedTrip: UUID?
    private var enabled = false
    private var foreground = false
    private let report: (String?) -> Void

    init(report: @escaping (String?) -> Void) {
        self.report = report
        // Never display or act on a route from a previous app process.
        worker = Task { [weak self] in
            for stale in Activity<RouteActivityAttributes>.activities {
                await stale.end(using: nil, dismissalPolicy: .immediate)
            }
            self?.worker = nil
            self?.drain()
        }
    }

    func sync(_ state: RouteActivityState?, enabled: Bool, foreground: Bool) {
        let preferenceChanged = self.enabled != enabled
        let becameForeground = foreground && !self.foreground
        self.enabled = enabled
        self.foreground = foreground
        if preferenceChanged { suppressedTrip = nil }
        let accepted = policy.accept(state, at: ProcessInfo.processInfo.systemUptime)
        guard accepted || preferenceChanged || becameForeground else { return }
        desired = state
        generation += 1
        drain()
    }

    private func drain() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self = self else { return }
            var applied = -1
            while applied != self.generation {
                applied = self.generation
                await self.apply()
            }
            self.worker = nil
        }
    }

    func flush() async { await worker?.value }

    private func apply() async {
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled, let state = desired else {
            if let old = activity {
                activity = nil
                await old.end(using: nil, dismissalPolicy: .immediate)
            }
            report(nil)
            return
        }
        if let old = activity, old.attributes.tripID != state.tripID {
            activity = nil
            await old.end(using: nil, dismissalPolicy: .immediate)
            // A newer state may have arrived while ending the previous trip.
            generation += 1
            return
        }
        let content = RouteActivityAttributes.ContentState(route: state, updatedAt: Date())
        if let activity = activity {
            if activity.activityState == .dismissed || activity.activityState == .ended {
                // Respect dismissal and the system lifetime limit. Do not respawn.
                suppressedTrip = state.tripID
                self.activity = nil
                report("The Live Activity has ended. Route simulation continues.")
                return
            }
            await activity.update(using: content)
        } else if foreground, suppressedTrip != state.tripID {
            do {
                activity = try Activity.request(attributes: RouteActivityAttributes(tripID: state.tripID),
                    contentState: content, pushType: nil)
                report(nil)
            } catch {
                suppressedTrip = state.tripID
                report("Couldn't start Live Activity: " + error.localizedDescription)
            }
        }
    }
}
