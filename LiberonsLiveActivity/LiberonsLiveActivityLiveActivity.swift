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
    private func remaining(_ state: LiberonsLiveActivityAttributes.ContentState) -> Int {
        max(0, state.total - state.completed - state.failed)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiberonsLiveActivityAttributes.self) { context in
            VStack(spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.blue)

                    Text("Libérons")
                        .font(.system(size: 16, weight: .semibold))

                    Text("· Sauvegarde")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text("\(context.state.percent)%")
                        .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                }

                ProgressView(value: Double(context.state.percent), total: 100)
                    .progressViewStyle(.linear)
                    .tint(.blue)

                HStack(spacing: 8) {
                    if context.state.failed > 0 {
                        Text("\(context.state.completed) protégés · \(context.state.failed) échecs")
                    } else {
                        Text("\(context.state.completed) protégés")
                    }

                    Spacer()

                    Text("\(remaining(context.state)) restants")
                }
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .foregroundStyle(.blue)
                        Text("Libérons")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.percent)%")
                        .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 7) {
                        ProgressView(value: Double(context.state.percent), total: 100)
                            .progressViewStyle(.linear)
                            .tint(.blue)

                        HStack {
                            Text("\(context.state.completed) protégés")
                            Spacer()
                            Text("\(remaining(context.state)) restants")
                        }
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text("\(context.state.percent)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            } minimal: {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .foregroundStyle(.blue)
            }
            .keylineTint(.blue)
        }
    }
}

#Preview("Sauvegarde", as: .content, using: LiberonsLiveActivityAttributes(startedAt: .now)) {
    LiberonsLiveActivityLiveActivity()
} contentStates: {
    LiberonsLiveActivityAttributes.ContentState(completed: 27, failed: 0, total: 1034, percent: 3, status: "Sauvegarde en cours")
}
