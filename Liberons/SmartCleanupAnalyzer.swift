import Foundation
import Combine
import Photos

@MainActor
final class SmartCleanupAnalyzer: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var screenshotIDs: [String] = []
    @Published private(set) var duplicateIDs: [String] = []
    @Published private(set) var memoryIDs: [String] = []
    @Published private(set) var screenshotBytes: Int64 = 0
    @Published private(set) var duplicateBytes: Int64 = 0

    var screenshotCount: Int { screenshotIDs.count }
    var duplicateCount: Int { duplicateIDs.count }
    var memoryCount: Int { memoryIDs.count }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        // Keep the first pass local and lightweight. The previous implementation exported
        // every possible duplicate (including iCloud originals) and SHA-256 hashed entire
        // files. On large libraries this could make the app appear frozen for minutes.
        let result = PHAsset.fetchAssets(with: nil)
        var shots: [String] = []
        var memories: [String] = []

        result.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image && asset.mediaSubtypes.contains(.photoScreenshot) {
                shots.append(asset.localIdentifier)
            } else {
                memories.append(asset.localIdentifier)
            }
        }

        screenshotIDs = shots
        memoryIDs = memories

        // Exact duplicate verification is intentionally not part of this foreground scan.
        // We never label/delete a media item as a duplicate without content verification.
        duplicateIDs = []
        screenshotBytes = 0
        duplicateBytes = 0
    }

    func deleteScreenshots() async throws { try await delete(ids: screenshotIDs) }
    func deleteDuplicates() async throws { try await delete(ids: duplicateIDs) }
    func deleteAllCleanupItems() async throws { try await delete(ids: Array(Set(screenshotIDs + duplicateIDs))) }

    private func delete(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
        await scan()
    }
}
