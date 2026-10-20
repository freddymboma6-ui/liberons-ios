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
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)

                    Text("Libérons")
                        .font(.system(size: 16, weight: .semibold))

                    Text("Sauvegarde")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text("\(context.state.percent)%")
                        .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                ProgressView(value: Double(context.state.percent), total: 100)
                    .progressViewStyle(.linear)
                    .tint(.blue)

                HStack(spacing: 12) {
                    Text(context.state.failed > 0
                         ? "\(context.state.completed) protégés · \(context.state.failed) échecs"
                         : "\(context.state.completed) protégés")
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer(minLength: 8)

                    Text("\(remaining(context.state)) restants")
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .foregroundStyle(.blue)
                        Text("Libérons")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.percent)%")
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 7) {
                        ProgressView(value: Double(context.state.percent), total: 100)
                            .progressViewStyle(.linear)
                            .tint(.blue)

                        HStack(spacing: 10) {
                            Text("\(context.state.completed) protégés")
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(remaining(context.state)) restants")
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 2)
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
    LiberonsLiveActivityAttributes.ContentState(completed: 14, failed: 0, total: 1034, percent: 1, status: "Sauvegarde en cours")
}
