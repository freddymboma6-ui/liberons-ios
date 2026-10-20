import ActivityKit
import WidgetKit
import SwiftUI

struct LiberonsLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var completed: Int
        var failed: Int
        var total: Int
        var percent: Int
        var status: String
    }

    var startedAt: Date
}

struct LiberonsLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiberonsLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .foregroundStyle(.blue)
                    Text("Libérons")
                        .font(.headline)
                    Spacer()
                    Text("\(context.state.percent)%")
                        .font(.headline.monospacedDigit())
                }

                Text(context.state.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(context.state.percent), total: 100)
                    .tint(.blue)

                HStack {
                    Text("\(context.state.completed) / \(context.state.total) éléments")
                    Spacer()
                    if context.state.failed > 0 {
                        Text("\(context.state.failed) échec(s)")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .activityBackgroundTint(.black.opacity(0.92))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Libérons", systemImage: "icloud.and.arrow.up.fill")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.percent)%")
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(context.state.percent), total: 100)
                            .tint(.blue)
                        HStack {
                            Text(context.state.status)
                            Spacer()
                            Text("\(context.state.completed)/\(context.state.total)")
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: "icloud.and.arrow.up.fill")
            } compactTrailing: {
                Text("\(context.state.percent)%")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "icloud.and.arrow.up.fill")
            }
            .keylineTint(.blue)
        }
    }
}

#Preview("Sauvegarde", as: .content, using: LiberonsLiveActivityAttributes(startedAt: .now)) {
    LiberonsLiveActivityLiveActivity()
} contentStates: {
    LiberonsLiveActivityAttributes.ContentState(completed: 2840, failed: 0, total: 4120, percent: 69, status: "Sauvegarde en cours")
}
