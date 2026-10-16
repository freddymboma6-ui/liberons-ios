import Foundation
import Photos
import Combine
import CryptoKit

struct StorageInsightItem: Identifiable, Hashable, Codable {
    enum Kind: String, Hashable, Codable {
        case duplicate, screenshot, video, largeVideo, longVideo, slowMotion, timeLapse, livePhoto, rawPhoto, video4K, other
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

private struct StorageAnalysisCache: Codable {
    let items: [StorageInsightItem]
    let duplicates: [StorageInsightItem]
    let lastScanDate: Date
    let assetCount: Int
}

private struct AssetCandidate {
    let asset: PHAsset
    let item: StorageInsightItem
    let primaryResource: PHAssetResource?
    let mediaType: PHAssetMediaType
}

@MainActor
final class StorageIntelligence: ObservableObject {
    @Published private(set) var items: [StorageInsightItem] = []
    @Published private(set) var duplicateItems: [StorageInsightItem] = []
    @Published private(set) var categories: [StorageInsightCategory] = []
    @Published private(set) var deviceCapacityBytes: Int64 = 0
    @Published private(set) var deviceAvailableBytes: Int64 = 0
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?

    private let cacheURL: URL
    private var cachedAssetCount = 0

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheURL = base.appendingPathComponent("liberons-storage-analysis-v2.json")
        loadCache()
    }

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

    func refreshInBackgroundIfNeeded() async {
        refreshDeviceStorage()
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        let currentCount = PHAsset.fetchAssets(with: nil).count
        let stale = lastScanDate.map { Date().timeIntervalSince($0) > 6 * 60 * 60 } ?? true
        guard items.isEmpty || currentCount != cachedAssetCount || stale else { return }
        await scan()
    }

    func scan() async {
        guard !isScanning else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        isScanning = true
        refreshDeviceStorage()

        let scanResult = await Task.detached(priority: .utility) { () -> ([StorageInsightItem], [StorageInsightItem], Int) in
            let assets = PHAsset.fetchAssets(with: nil)
            var output: [StorageInsightItem] = []
            var candidates: [AssetCandidate] = []
            output.reserveCapacity(assets.count)
            candidates.reserveCapacity(assets.count)

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
                    if subtypes.contains(.photoScreenshot) { kind = .screenshot }
                    else if subtypes.contains(.videoHighFrameRate) { kind = .slowMotion }
                    else if subtypes.contains(.videoTimelapse) { kind = .timeLapse }
                    else if subtypes.contains(.photoLive) { kind = .livePhoto }
                    else if asset.mediaType == .video {
                        if asset.pixelWidth >= 3840 || asset.pixelHeight >= 2160 { kind = .video4K }
                        else if asset.duration >= 300 { kind = .longVideo }
                        else if bytes >= 500_000_000 { kind = .largeVideo }
                        else { kind = .video }
                    } else if names.contains(where: { $0.hasSuffix(".dng") }) { kind = .rawPhoto }

                    let item = StorageInsightItem(id: asset.localIdentifier, kind: kind, bytes: bytes, duration: asset.duration, creationDate: asset.creationDate, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
                    if kind != .other || bytes >= 100_000_000 { output.append(item) }
                    if bytes > 0, let primary = resources.first { candidates.append(AssetCandidate(asset: asset, item: item, primaryResource: primary, mediaType: asset.mediaType)) }
                }
            }

            // First narrow the library using safe metadata. Only small candidate groups are read.
            // Then compare SHA-256 of the local original bytes before calling anything a duplicate.
            let grouped = Dictionary(grouping: candidates) { candidate in
                "\(candidate.mediaType.rawValue)|\(candidate.item.pixelWidth)x\(candidate.item.pixelHeight)|\(Int(candidate.item.duration.rounded()))|\(candidate.item.bytes)"
            }
            var duplicateOutput: [StorageInsightItem] = []
            let manager = PHAssetResourceManager.default()
            for group in grouped.values where group.count > 1 && group.count <= 50 {
                var hashes: [String: [AssetCandidate]] = [:]
                for candidate in group {
                    guard let resource = candidate.primaryResource else { continue }
                    var hasher = SHA256()
                    var failed = false
                    let semaphore = DispatchSemaphore(value: 0)
                    let options = PHAssetResourceRequestOptions()
                    options.isNetworkAccessAllowed = false
                    manager.requestData(for: resource, options: options, dataReceivedHandler: { data in
                        hasher.update(data: data)
                    }, completionHandler: { error in
                        failed = error != nil
                        semaphore.signal()
                    })
                    semaphore.wait()
                    guard !failed else { continue }
                    let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    hashes[digest, default: []].append(candidate)
                }
                for matches in hashes.values where matches.count > 1 {
                    // Keep the oldest copy by default; only extra byte-identical copies are recoverable.
                    let ordered = matches.sorted { ($0.item.creationDate ?? .distantPast) < ($1.item.creationDate ?? .distantPast) }
                    for extra in ordered.dropFirst() {
                        duplicateOutput.append(StorageInsightItem(id: extra.item.id, kind: .duplicate, bytes: extra.item.bytes, duration: extra.item.duration, creationDate: extra.item.creationDate, pixelWidth: extra.item.pixelWidth, pixelHeight: extra.item.pixelHeight))
                    }
                }
            }
            return (output.sorted { $0.bytes > $1.bytes }, duplicateOutput.sorted { $0.bytes > $1.bytes }, assets.count)
        }.value

        items = scanResult.0
        duplicateItems = scanResult.1
        cachedAssetCount = scanResult.2
        rebuildCategories()
        lastScanDate = Date()
        saveCache()
        refreshDeviceStorage()
        isScanning = false
    }

    func items(for kind: StorageInsightItem.Kind) -> [StorageInsightItem] {
        if kind == .duplicate { return duplicateItems }
        return items.filter { $0.kind == kind }.sorted { $0.bytes > $1.bytes }
    }

    private func rebuildCategories() {
        let grouped = Dictionary(grouping: items, by: \.kind)
        var built = grouped.map { kind, values in
            StorageInsightCategory(kind: kind, count: values.count, bytes: values.reduce(0) { $0 + $1.bytes })
        }
        if !duplicateItems.isEmpty {
            built.append(StorageInsightCategory(kind: .duplicate, count: duplicateItems.count, bytes: duplicateItems.reduce(0) { $0 + $1.bytes }))
        }
        categories = built.sorted { $0.bytes > $1.bytes }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(StorageAnalysisCache.self, from: data) else { return }
        items = cache.items
        duplicateItems = cache.duplicates
        lastScanDate = cache.lastScanDate
        cachedAssetCount = cache.assetCount
        rebuildCategories()
    }

    private func saveCache() {
        guard let date = lastScanDate else { return }
        let cache = StorageAnalysisCache(items: items, duplicates: duplicateItems, lastScanDate: date, assetCount: cachedAssetCount)
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
    }
}
