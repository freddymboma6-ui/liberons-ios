import Foundation
import Combine
import Photos

@MainActor
final class SmartCleanupAnalyzer: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var screenshotIDs: [String] = []
    @Published private(set) var duplicateIDs: [String] = []
    @Published private(set) var memoryIDs: [String] = []
    @Published private(set) var photoIDs: [String] = []
    @Published private(set) var videoIDs: [String] = []
    @Published private(set) var screenshotBytes: Int64 = 0
    @Published private(set) var photoBytes: Int64 = 0
    @Published private(set) var videoBytes: Int64 = 0
    @Published private(set) var duplicateBytes: Int64 = 0

    var screenshotCount: Int { screenshotIDs.count }
    var duplicateCount: Int { duplicateIDs.count }
    var memoryCount: Int { memoryIDs.count }
    var photoCount: Int { photoIDs.count }
    var videoCount: Int { videoIDs.count }
    var totalCount: Int { photoCount + videoCount + screenshotCount }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let result = PHAsset.fetchAssets(with: nil)
        var shots: [String] = []
        var photos: [String] = []
        var videos: [String] = []
        var memories: [String] = []

        result.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image && asset.mediaSubtypes.contains(.photoScreenshot) {
                shots.append(asset.localIdentifier)
            } else if asset.mediaType == .video {
                videos.append(asset.localIdentifier)
                memories.append(asset.localIdentifier)
            } else if asset.mediaType == .image {
                photos.append(asset.localIdentifier)
                memories.append(asset.localIdentifier)
            }
        }

        screenshotIDs = shots
        photoIDs = photos
        videoIDs = videos
        memoryIDs = memories
        duplicateIDs = []
        duplicateBytes = 0

        async let shotBytes = localByteCount(for: shots)
        async let photosBytes = localByteCount(for: photos)
        async let videosBytes = localByteCount(for: videos)
        screenshotBytes = await shotBytes
        photoBytes = await photosBytes
        videoBytes = await videosBytes
    }

    func deleteScreenshots() async throws { try await delete(ids: screenshotIDs) }
    func deleteDuplicates() async throws { try await delete(ids: duplicateIDs) }
    func deleteAllCleanupItems() async throws { try await delete(ids: Array(Set(screenshotIDs + duplicateIDs))) }

    private func localByteCount(for ids: [String]) async -> Int64 {
        guard !ids.isEmpty else { return 0 }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var total: Int64 = 0
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            for resource in PHAssetResource.assetResources(for: asset) {
                total += await localByteCount(for: resource)
            }
        }
        return total
    }

    private func localByteCount(for resource: PHAssetResource) async -> Int64 {
        await withCheckedContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false
            var bytes: Int64 = 0
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in bytes += Int64(data.count) },
                completionHandler: { error in continuation.resume(returning: error == nil ? bytes : 0) }
            )
        }
    }

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
