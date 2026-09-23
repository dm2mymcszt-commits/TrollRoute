import Foundation

/// ActivityKit transports this value; it never owns or advances the route.
/// No coordinates or location privileges are needed in the widget process.
struct RouteActivityState: Codable, Hashable {
    struct StopChoice: Codable, Hashable, Identifiable {
        let id: String
        let title: String
    }
    struct Stop: Codable, Hashable {
        let id: UUID
        let choices: [StopChoice]
        let preselection: String
    }

    let tripID: UUID
    let progress: Double
    let remainingSeconds: Double
    let remainingMeters: Double
    let speedKmh: Double
    let destination: String
    let paused: Bool
    let stop: Stop?
    // Used to identify leg/configuration changes, never extra visible content.
    let leg: Int
    let finishAction: String

    /// Bound by UTF-8 bytes, including pathological combining-character names.
    /// This leaves room under ActivityKit's 4 KB attributes + content limit.
    static func destinationName(_ text: String?, fallback: String) -> String {
        let name = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = name.isEmpty ? fallback : name
        var result = ""
        var bytes = 0
        for scalar in source.unicodeScalars {
            let size = String(scalar).utf8.count
            guard bytes + size <= 384 else { break }
            result.unicodeScalars.append(scalar)
            bytes += size
        }
        return result
    }
}

/// Both in-process iOS17 intents and older-OS links cross this same boundary.
/// A Stop answer always carries the ID of the immutable press-time capture.
struct RouteActivityCommand: Equatable {
    enum Action: String {
        case pause, resume, requestStop, cancelStop, chooseStop
    }
    let tripID: UUID
    let action: Action
    var requestID: UUID? = nil
    var choice: String? = nil

    enum Outcome: Equatable {
        case applied
        case openPlacePicker(UUID)
        case unavailable
    }

    /// Older iOS controls open the app. The specific-place handoff also opens
    /// UI on iOS17; no link is allowed to skip directly to a destructive choice.
    var foregroundURL: URL? {
        var parts = URLComponents()
        parts.scheme = "trollroute"
        parts.host = "route"
        parts.path = "/" + tripID.uuidString + "/" + action.rawValue
        switch action {
        case .pause, .resume, .requestStop:
            guard requestID == nil, choice == nil else { return nil }
        case .chooseStop:
            guard let requestID = requestID, choice == "specific" else { return nil }
            parts.queryItems = [URLQueryItem(name: "request", value: requestID.uuidString),
                                URLQueryItem(name: "choice", value: "specific")]
        case .cancelStop: return nil
        }
        return parts.url
    }

    static func fromForegroundURL(_ url: URL) -> Self? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "trollroute", parts.host == "route",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else { return nil }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 3, path[0].isEmpty, let trip = UUID(uuidString: String(path[1])),
              let action = Action(rawValue: String(path[2])) else { return nil }
        let items = parts.queryItems ?? []
        switch action {
        case .pause, .resume, .requestStop:
            guard items.isEmpty else { return nil }
            return Self(tripID: trip, action: action)
        case .chooseStop:
            guard items.count == 2, items.filter({ $0.name == "request" }).count == 1,
                  items.filter({ $0.name == "choice" && $0.value == "specific" }).count == 1,
                  let value = items.first(where: { $0.name == "request" })?.value,
                  let request = UUID(uuidString: value) else { return nil }
            return Self(tripID: trip, action: action, requestID: request, choice: "specific")
        case .cancelStop: return nil
        }
    }
}
