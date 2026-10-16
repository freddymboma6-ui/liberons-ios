import Foundation
import UIKit

/// Keeps Libérons from becoming a second photo library on the device.
/// Cloud originals are never persisted here. This guard only manages transient/cache data.
enum LocalStorageGuard {
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
        purgeTemporaryFiles(removeAll: true)
    }

    static func purgeTemporaryFiles(removeAll: Bool = false) {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
        guard let urls = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-maxTemporaryFileAge)
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            if removeAll || (values.contentModificationDate ?? .distantPast) < cutoff { try? manager.removeItem(at: url) }
        }
    }

    /// User-generated cloud originals are intentionally excluded: this measures only
    /// Libérons' local cache + temporary working files that can be reclaimed.
    static func reclaimableBytes() -> Int64 {
        directoryBytes(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) + directoryBytes(FileManager.default.temporaryDirectory)
    }

    static func formattedReclaimableSize() -> String {
        let bytes = reclaimableBytes()
        return bytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func directoryBytes(_ directory: URL?) -> Int64 {
        guard let directory else { return 0 }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func applicationDidEnterBackground() { purgeTemporaryFiles() }
    static func applicationDidReceiveMemoryWarning() { URLCache.shared.removeAllCachedResponses() }
}
