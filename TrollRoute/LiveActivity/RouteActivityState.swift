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
}
