import Foundation
import Combine
import UIKit

/// The view and LiveActivityIntent use this same app-process route session.
/// A process relaunch has no running route; old controls cannot recreate one.
@MainActor
final class RouteRuntime {
    static let shared = RouteRuntime()
    let simulator: RouteSimulator
    private var publisher: RouteActivityPublishing?
    private var subscriptions = Set<AnyCancellable>()

    private init() {
        simulator = RouteSimulator()
        if #available(iOS 16.1, *) {
            publisher = RouteActivityController { message in
                let preferences = RouteActivityPreferences.shared
                if preferences.message != message { preferences.message = message }
            }
        }
        // @Published emits before mutation; enqueue once onto the main run loop
        // to read the complete engine state, then coalesce duplicate snapshots.
        simulator.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshActivity()
        }.store(in: &subscriptions)
        RouteActivityPreferences.shared.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshActivity()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification))
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshActivity() }
            .store(in: &subscriptions)
        refreshActivity()
    }

    private func refreshActivity() {
        let preferences = RouteActivityPreferences.shared
        publisher?.sync(simulator.activitySnapshot,
            enabled: preferences.enabled && preferences.availability == .supported,
            foreground: UIApplication.shared.applicationState == .active)
    }

    @discardableResult
    func perform(_ command: RouteActivityCommand) -> RouteActivityCommand.Outcome {
        let result = simulator.performActivityCommand(command)
        refreshActivity()
        return result
    }

    func performIntent(_ command: RouteActivityCommand) async -> RouteActivityCommand.Outcome {
        let result = perform(command)
        await publisher?.flush()
        return result
    }
}
