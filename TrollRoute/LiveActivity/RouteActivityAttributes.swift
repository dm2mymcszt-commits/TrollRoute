import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct RouteActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let route: RouteActivityState
        let updatedAt: Date

        var arrival: Date { updatedAt.addingTimeInterval(route.remainingSeconds) }
        var progressInterval: ClosedRange<Date> {
            let total = route.progress < 1 ? route.remainingSeconds / (1 - route.progress) : 0
            return updatedAt.addingTimeInterval(-total * route.progress)...arrival
        }
    }
    let tripID: UUID
}
