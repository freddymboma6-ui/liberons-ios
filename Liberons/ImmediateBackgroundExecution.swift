import UIKit

/// Bridges the gap between the moment Libérons is backgrounded and the point
/// where iOS may grant a BGProcessing window. Background URLSession still owns
/// the network transfers; this short system-granted window lets PhotoKit/export/
/// hashing keep feeding that queue immediately after the screen locks.
@MainActor
final class ImmediateBackgroundExecution {
    static let shared = ImmediateBackgroundExecution()

    private var taskIdentifier: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func begin() {
        guard taskIdentifier == .invalid else { return }
        taskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "Libérons backup queue") { [weak self] in
            Task { @MainActor in
                self?.end()
            }
        }
        if taskIdentifier != .invalid {
            print("[BackgroundBackup] Immediate background execution started")
        }
    }

    func end() {
        guard taskIdentifier != .invalid else { return }
        let identifier = taskIdentifier
        taskIdentifier = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
        print("[BackgroundBackup] Immediate background execution ended")
    }
}
