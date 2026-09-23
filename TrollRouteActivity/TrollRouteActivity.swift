import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TrollRouteActivityBundle: WidgetBundle {
    var body: some Widget { TrollRouteActivity() }
}

struct TrollRouteActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RouteActivityAttributes.self) { context in
            RouteActivityBody(content: context.state)
                .padding(12)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    RouteActivityBody(content: context.state)
                }
            } compactLeading: {
                Text(context.state.route.progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().font(.caption)
            } compactTrailing: {
                RouteActivityTime(content: context.state).font(.caption).frame(maxWidth: 58)
            } minimal: {
                ProgressView(value: context.state.route.progress)
                    .progressViewStyle(.circular)
            }
            .widgetURL(URL(string: "trollroute://route"))
            .keylineTint(.accentColor)
        }
    }
}

struct RouteActivityTime: View {
    let content: RouteActivityAttributes.ContentState
    var body: some View {
        if content.route.paused || content.route.remainingSeconds <= 0 {
            Text(Self.duration(content.route.remainingSeconds)).monospacedDigit()
        } else {
            Text(timerInterval: content.updatedAt...content.arrival, countsDown: true)
                .monospacedDigit()
        }
    }
    static func duration(_ seconds: Double) -> String {
        let value = max(0, Int(ceil(seconds)))
        return value >= 3600 ? "\(value / 3600)h \(value / 60 % 60)m" : "\(value / 60)m \(value % 60)s"
    }
}

struct RouteActivityBody: View {
    let content: RouteActivityAttributes.ContentState
    private var route: RouteActivityState { content.route }
    var body: some View {
        if #available(iOS 17.0, *), let stop = route.stop {
            stopChoices(stop)
        } else {
            VStack(spacing: 7) {
                Text(route.destination).font(.subheadline.weight(.semibold))
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    Text(route.progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().frame(minWidth: 35, alignment: .leading)
                    if route.paused || route.remainingSeconds <= 0 {
                        ProgressView(value: route.progress)
                    } else {
                        ProgressView(timerInterval: content.progressInterval, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: { EmptyView() }
                    }
                }
                HStack {
                    RouteActivityTime(content: content).frame(maxWidth: .infinity, alignment: .leading)
                    Text(route.remainingMeters >= 1000
                         ? String(format: "%.1f km", route.remainingMeters / 1000)
                         : "\(Int(ceil(route.remainingMeters))) m")
                    Spacer(minLength: 8)
                    Text("\(Int(route.speedKmh.rounded())) km/h")
                }.font(.caption).monospacedDigit()
                HStack(spacing: 12) {
                    control(route.paused ? "Resume" : "Pause", action: route.paused ? .resume : .pause)
                    control("Stop", action: .requestStop)
                }
            }
        }
    }

    @ViewBuilder
    private func control(_ title: String, action: RouteActivityCommand.Action) -> some View {
        let command = RouteActivityCommand(tripID: route.tripID, action: action)
        if #available(iOS 17.0, *) {
            Button(intent: RouteActivityIntent(command)) { controlLabel(title) }.buttonStyle(.plain)
        } else if let url = command.foregroundURL {
            Link(destination: url) { controlLabel(title) }
        }
    }

    private func controlLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }

    @available(iOS 17.0, *)
    private func stopChoices(_ stop: RouteActivityState.Stop) -> some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(stop.choices) { choice in
                    let command = RouteActivityCommand(tripID: route.tripID, action: .chooseStop,
                        requestID: stop.id, choice: choice.id)
                    if choice.id == "specific", let url = command.foregroundURL {
                        Link(destination: url) { choiceLabel(choice, selected: choice.id == stop.preselection) }
                    } else {
                        Button(intent: RouteActivityIntent(command)) {
                            choiceLabel(choice, selected: choice.id == stop.preselection)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button(intent: RouteActivityIntent(.init(tripID: route.tripID, action: .cancelStop, requestID: stop.id))) {
                Text("Cancel").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 28)
            }.buttonStyle(.plain)
        }
    }

    private func choiceLabel(_ choice: RouteActivityState.StopChoice, selected: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            Text(choice.title).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption).frame(maxWidth: .infinity, minHeight: 38).padding(.horizontal, 6)
        .background(Color.accentColor.opacity(selected ? 0.25 : 0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}
