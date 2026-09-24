// A separate test-only app is necessary: iOS chooses minimal Island views
// from different apps, not two activities belonging to the same app.
import ActivityKit
import SwiftUI
import WidgetKit

struct CompanionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var active = true }
}

#if COMPANION_WIDGET
@main struct CompanionWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompanionAttributes.self) { _ in
            Text("QA companion")
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) { Text("QA companion") }
            } compactLeading: { Text("QA") }
              compactTrailing: { Text("2") }
              minimal: { Text("QA").accessibilityIdentifier("qa-companion-minimal") }
        }
    }
}
#else
@main struct CompanionApp: App {
    @State private var activity: Activity<CompanionAttributes>?
    var body: some Scene {
        WindowGroup {
            VStack {
                Button("Start companion") {
                    activity = try! Activity.request(attributes: CompanionAttributes(),
                        contentState: .init(), pushType: nil)
                }
                Button("End companion") {
                    Task {
                        await activity?.end(using: nil, dismissalPolicy: .immediate)
                        activity = nil
                    }
                }
                Text(activity == nil ? "Companion ended" : "Companion ready")
            }
        }
    }
}
#endif
