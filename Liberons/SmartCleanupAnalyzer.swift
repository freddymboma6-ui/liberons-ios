import Foundation
import Photos

@MainActor
final class SmartCleanupAnalyzer: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var screenshotIDs: [String] = []
    @Published private(set) var memoryIDs: [String] = []
    @Published private(set) var screenshotBytes: Int64 = 0

    var screenshotCount: Int { screenshotIDs.count }
    var memoryCount: Int { memoryIDs.count }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let result = PHAsset.fetchAssets(with: nil)
        var shots: [String] = []
        var memories: [String] = []
        var bytes: Int64 = 0
        result.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image && asset.mediaSubtypes.contains(.photoScreenshot) {
                shots.append(asset.localIdentifier)
                if let resource = PHAssetResource.assetResources(for: asset).first {
                    bytes += Int64(resource.value(forKey: "fileSize") as? CLong ?? 0)
                }
            } else {
                memories.append(asset.localIdentifier)
            }
        }
        screenshotIDs = shots
        memoryIDs = memories
        screenshotBytes = bytes
    }

    func deleteScreenshots() async throws {
        guard !screenshotIDs.isEmpty else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: screenshotIDs, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets as NSArray) }
        await scan()
    }
}
