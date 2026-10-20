import BackgroundTasks
import Foundation

/// Gives iOS a supported way to wake Libérons after suspension so queued backup
/// work can be continued. Background URLSession remains responsible for uploads
/// that are already in flight.
final class BackgroundBackupScheduler {
    static let shared = BackgroundBackupScheduler()
    static let processingIdentifier = "com.liberons.Liberons.backup-processing"

    private let lock = NSLock()
    private var handler: (@Sendable () async -> Void)?

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.run(task)
        }
    }

    func setResumeHandler(_ handler: (@Sendable () async -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func schedule() {
        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundBackup] Unable to schedule processing: \(error.localizedDescription)")
        }
    }

    func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.processingIdentifier)
    }

    private func run(_ task: BGProcessingTask) {
        schedule()
        let work = Task {
            lock.lock()
            let handler = self.handler
            lock.unlock()
            guard let handler else {
                task.setTaskCompleted(success: false)
                return
            }
            await handler()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
