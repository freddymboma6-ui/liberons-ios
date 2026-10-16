import Foundation

extension BackupEngine {
    // Temporary compatibility for the existing single-item card.
    // The behavior is intentionally oldest-first now.
    func backupOneNewestAsset() async {
        await backupOneOldestAsset()
    }
}
