import Foundation
import Photos
import Combine

struct StorageInsightItem: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case screenshot, video, largeVideo, longVideo, slowMotion, timeLapse, livePhoto, rawPhoto, video4K, other
    }
    let id: String
    let kind: Kind
    let bytes: Int64
    let duration: TimeInterval
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
}

struct StorageInsightCategory: Identifiable, Hashable {
    let kind: StorageInsightItem.Kind
    let count: Int
    let bytes: Int64
    var id: StorageInsightItem.Kind { kind }
}

@MainActor
final class StorageIntelligence: ObservableObject {
    @Published private(set) var items: [StorageInsightItem] = []
    @Published private(set) var categories: [StorageInsightCategory] = []
    @Published private(set) var deviceCapacityBytes: Int64 = 0
    @Published private(set) var deviceAvailableBytes: Int64 = 0
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?

    var recoverableBytes: Int64 { items.reduce(0) { $0 + max(0, $1.bytes) } }
    var projectedAvailableBytes: Int64 { min(deviceCapacityBytes, deviceAvailableBytes + recoverableBytes) }
    var largestItems: [StorageInsightItem] { Array(items.sorted { $0.bytes > $1.bytes }.prefix(50)) }

    func refreshDeviceStorage() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            deviceCapacityBytes = Int64(values.volumeTotalCapacity ?? 0)
            deviceAvailableBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
    }

    func scan() async {
        guard !isScanning else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        isScanning = true
        refreshDeviceStorage()

        let result = await Task.detached(priority: .utility) { () -> [StorageInsightItem] in
            let assets = PHAsset.fetchAssets(with: nil)
            var output: [StorageInsightItem] = []
            output.reserveCapacity(assets.count)

            for index in 0..<assets.count {
                autoreleasepool {
                    let asset = assets.object(at: index)
                    let resources = PHAssetResource.assetResources(for: asset)
                    var bytes: Int64 = 0
                    var names: [String] = []
                    for resource in resources {
                        if let size = resource.value(forKey: "fileSize") as? NSNumber { bytes += size.int64Value }
                        names.append(resource.originalFilename.lowercased())
                    }

                    let subtypes = asset.mediaSubtypes
                    var kind: StorageInsightItem.Kind = .other
                    if subtypes.contains(.photoScreenshot) {
                        kind = .screenshot
                    } else if subtypes.contains(.videoHighFrameRate) {
                        kind = .slowMotion
                    } else if subtypes.contains(.videoTimelapse) {
                        kind = .timeLapse
                    } else if subtypes.contains(.photoLive) {
                        kind = .livePhoto
                    } else if asset.mediaType == .video {
                        // Screen recordings intentionally remain in the Video family. This avoids
                        // pretending Photos exposes a perfectly reliable screen-recording subtype.
                        if asset.pixelWidth >= 3840 || asset.pixelHeight >= 2160 {
                            kind = .video4K
                        } else if asset.duration >= 300 {
                            kind = .longVideo
                        } else if bytes >= 500_000_000 {
                            kind = .largeVideo
                        } else {
                            kind = .video
                        }
                    } else if names.contains(where: { $0.hasSuffix(".dng") }) {
                        kind = .rawPhoto
                    }

                    if kind != .other || bytes >= 100_000_000 {
                        output.append(StorageInsightItem(id: asset.localIdentifier, kind: kind, bytes: bytes, duration: asset.duration, creationDate: asset.creationDate, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight))
                    }
                }
            }
            return output
        }.value

        items = result.sorted { $0.bytes > $1.bytes }
        let grouped = Dictionary(grouping: items, by: \.kind)
        categories = grouped.map { kind, values in
            StorageInsightCategory(kind: kind, count: values.count, bytes: values.reduce(0) { $0 + $1.bytes })
        }.sorted { $0.bytes > $1.bytes }
        lastScanDate = Date()
        refreshDeviceStorage()
        isScanning = false
    }

    func items(for kind: StorageInsightItem.Kind) -> [StorageInsightItem] {
        items.filter { $0.kind == kind }.sorted { $0.bytes > $1.bytes }
    }
}
