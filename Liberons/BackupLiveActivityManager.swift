import ActivityKit
import Foundation

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

@MainActor
final class BackupLiveActivityManager {
    static let shared = BackupLiveActivityManager()

    private var activity: Activity<LiberonsLiveActivityAttributes>?

    private init() {
        activity = Activity<LiberonsLiveActivityAttributes>.activities.first
    }

    func start(total: Int) async {
        guard total > 0, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let existing = Activity<LiberonsLiveActivityAttributes>.activities.first {
            activity = existing
            await update(completed: 0, failed: 0, total: total, status: "Sauvegarde en cours")
            return
        }

        let attributes = LiberonsLiveActivityAttributes(startedAt: .now)
        let state = LiberonsLiveActivityAttributes.ContentState(
            completed: 0,
            failed: 0,
            total: total,
            percent: 0,
            status: "Sauvegarde en cours"
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("[LiveActivity] Unable to start: \(error.localizedDescription)")
        }
    }

    func update(completed: Int, failed: Int, total: Int, status: String = "Sauvegarde en cours") async {
        guard total > 0 else { return }
        let processed = min(total, max(0, completed + failed))
        let percent = min(100, max(0, Int((Double(processed) / Double(total) * 100).rounded())))
        let state = LiberonsLiveActivityAttributes.ContentState(
            completed: completed,
            failed: failed,
            total: total,
            percent: percent,
            status: status
        )
        await activity?.update(ActivityContent(state: state, staleDate: nil))
    }

    func finish(completed: Int, failed: Int, total: Int, stopped: Bool) async {
        guard let activity else { return }
        let processed = min(total, max(0, completed + failed))
        let percent = total > 0 ? min(100, max(0, Int((Double(processed) / Double(total) * 100).rounded()))) : 0
        let status: String
        if stopped {
            status = "Sauvegarde arrêtée"
        } else if failed > 0 {
            status = "Sauvegarde terminée avec des échecs"
        } else {
            status = "Sauvegarde terminée"
        }
        let state = LiberonsLiveActivityAttributes.ContentState(
            completed: completed,
            failed: failed,
            total: total,
            percent: percent,
            status: status
        )
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: stopped ? .immediate : .after(.now.addingTimeInterval(20))
        )
        self.activity = nil
    }
}
