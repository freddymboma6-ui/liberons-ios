import BackgroundTasks
import Foundation

/// Gives iOS a supported execution window after Libérons is suspended.
/// Background URLSession remains responsible for uploads already in flight;
/// BGProcessing lets the surrounding PhotoKit/hash/verify pipeline make progress
/// whenever iOS grants background processing time.
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
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.processingIdentifier)
        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundBackup] Processing requested")
        } catch {
            print("[BackgroundBackup] Unable to schedule processing: \(error.localizedDescription)")
        }
    }

    func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.processingIdentifier)
    }

    private func run(_ task: BGProcessingTask) {
        print("[BackgroundBackup] iOS granted a processing window")
        schedule()

        let work = Task {
            lock.lock()
            let handler = self.handler
            lock.unlock()

            if let handler {
                await handler()
            } else {
                // Do not voluntarily give the processing window back after only
                // a few seconds. The existing BackupEngine task resumes when the
                // process is running and keeps feeding URLSession.background.
                // iOS remains in control and will call expirationHandler when it
                // needs the execution window back.
                try? await Task.sleep(for: .minutes(15))
            }
            task.setTaskCompleted(success: !Task.isCancelled)
        }

        task.expirationHandler = {
            print("[BackgroundBackup] Processing window expired")
            work.cancel()
        }
    }
}
