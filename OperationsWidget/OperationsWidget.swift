import ActivityKit
import SwiftUI
import WidgetKit

@main
struct OperationsWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OperationActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.state == "ready" ? "checkmark.circle.fill" : "moon.stars.fill")
                    .font(.title).foregroundStyle(Color(red: 0.95, green: 0.79, blue: 0.5))
                VStack(alignment: .leading, spacing: 7) {
                    Text(context.state.title).font(.headline)
                    Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary)
                    if context.state.state == "running" || context.state.state == "queued" {
                        ProgressView(value: context.state.progress).tint(Color(red: 0.95, green: 0.79, blue: 0.5))
                    }
                }
            }.padding(18)
            .activityBackgroundTint(Color(red: 0.1, green: 0.16, blue: 0.24))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
            .widgetURL(URL(string: "bedtimestories://operation/" + context.attributes.operationID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "moon.stars.fill").foregroundStyle(.yellow) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.progress, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit()) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.title).font(.headline)
                        Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: context.state.progress).tint(.yellow)
                    }.padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.state == "ready" ? "checkmark" : "moon.stars.fill").foregroundStyle(.yellow)
            } compactTrailing: {
                ProgressView(value: context.state.progress).progressViewStyle(.circular).tint(.yellow).frame(width: 18, height: 18)
            } minimal: {
                Image(systemName: context.state.state == "ready" ? "checkmark" : "moon.stars.fill").foregroundStyle(.yellow)
            }.widgetURL(URL(string: "bedtimestories://operation/" + context.attributes.operationID))
        }
    }
}
