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

        let result = PHAsset.fetchAssets(with: nil)
        var shots: [String] = []
        var memories: [String] = []
        var shotBytes: Int64 = 0
        var groups: [String: [(id: String, date: Date, bytes: Int64)]] = [:]

        result.enumerateObjects { asset, _, _ in
            guard let resource = PHAssetResource.assetResources(for: asset).first else { return }
            let bytes = Int64(resource.value(forKey: "fileSize") as? CLong ?? 0)
            if asset.mediaType == .image && asset.mediaSubtypes.contains(.photoScreenshot) {
                shots.append(asset.localIdentifier)
                shotBytes += bytes
            } else {
                memories.append(asset.localIdentifier)
            }
            let key = "\(asset.mediaType.rawValue)|\(asset.pixelWidth)x\(asset.pixelHeight)|\(bytes)|\(resource.originalFilename.lowercased())"
            groups[key, default: []].append((asset.localIdentifier, asset.creationDate ?? .distantPast, bytes))
        }

        var duplicates: [String] = []
        var duplicateTotal: Int64 = 0
        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { $0.date < $1.date }
            for copy in ordered.dropFirst() {
                duplicates.append(copy.id)
                duplicateTotal += copy.bytes
            }
        }

        let duplicateSet = Set(duplicates)
        screenshotIDs = shots
        duplicateIDs = duplicates
        memoryIDs = memories.filter { !duplicateSet.contains($0) }
        screenshotBytes = shotBytes
        duplicateBytes = duplicateTotal
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
