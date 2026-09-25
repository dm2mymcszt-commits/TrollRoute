import AppIntents
import Foundation

@available(iOS 17.0, *)
struct RouteActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Control route"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false
    @Parameter(title: "Trip") var trip: String
    @Parameter(title: "Action") var action: String
    @Parameter(title: "Stop request") var request: String?
    @Parameter(title: "Location choice") var choice: String?

    init() {}
    init(_ command: RouteActivityCommand) {
        trip = command.tripID.uuidString
        action = command.action.rawValue
        request = command.requestID?.uuidString
        choice = command.choice
    }

    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "This route control is no longer available." }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: trip), let action = RouteActivityCommand.Action(rawValue: action) else {
            throw Failure.unavailable
        }
        let command = RouteActivityCommand(tripID: id, action: action,
            requestID: request.flatMap(UUID.init(uuidString:)), choice: choice)
        #if TROLLROUTE_APP
        guard await RouteRuntime.shared.performIntent(command) == .applied else { throw Failure.unavailable }
        #else
        // LiveActivityIntent must execute the app implementation. Never claim
        // success or create a second simulation if invoked in the extension.
        throw Failure.unavailable
        #endif
        return .result()
    }
}
