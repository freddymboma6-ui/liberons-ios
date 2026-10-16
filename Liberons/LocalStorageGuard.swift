import Foundation
import UIKit

/// Keeps Libérons from becoming a second photo library on the device.
/// Cloud originals are never persisted here. This guard only manages transient/cache data.
enum LocalStorageGuard {
    /// A deliberately small URL cache: enough for normal API responses and thumbnails,
    /// but never large enough to silently grow into gigabytes.
    static let memoryCacheLimit = 12 * 1024 * 1024
    static let diskCacheLimit = 64 * 1024 * 1024
    static let maxTemporaryFileAge: TimeInterval = 6 * 60 * 60

    static func configure() {
        URLCache.shared.memoryCapacity = memoryCacheLimit
        URLCache.shared.diskCapacity = diskCacheLimit
        URLCache.shared.removeCachedResponses(since: Date().addingTimeInterval(-24 * 60 * 60))
        purgeTemporaryFiles()
    }

    static func purgeTransientStorage() {
        URLCache.shared.removeAllCachedResponses()
        purgeTemporaryFiles()
    }

    static func purgeTemporaryFiles() {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
        guard let urls = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-maxTemporaryFileAge)
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            if (values.contentModificationDate ?? .distantPast) < cutoff {
                try? manager.removeItem(at: url)
            }
        }
    }

    static func applicationDidEnterBackground() {
        // Upload temp files are deleted by BackupEngine after each operation. This catches
        // leftovers from interrupted uploads/crashes without touching an active recent file.
        purgeTemporaryFiles()
    }

    static func applicationDidReceiveMemoryWarning() {
        URLCache.shared.removeAllCachedResponses()
    }
}
