import Foundation

/// The view and LiveActivityIntent use this same app-process route session.
/// A process relaunch has no running route; old controls cannot recreate one.
@MainActor
final class RouteRuntime {
    static let shared = RouteRuntime()
    let simulator: RouteSimulator

    private init() { simulator = RouteSimulator() }

    @discardableResult
    func perform(_ command: RouteActivityCommand) -> RouteActivityCommand.Outcome {
        simulator.performActivityCommand(command)
    }
}
