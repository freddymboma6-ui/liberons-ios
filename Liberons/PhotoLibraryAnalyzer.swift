import Foundation
import Photos
import Combine

@MainActor
final class PhotoLibraryAnalyzer: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var photoCount = 0
    @Published private(set) var videoCount = 0
    @Published private(set) var estimatedBytes: Int64 = 0
    @Published private(set) var scannedItems = 0
    @Published private(set) var totalItems = 0
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var libraryHasChanged = false
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard
    private let cacheVersion = 1

    private enum Key {
        static let version = "liberons.photoScan.version"
        static let photos = "liberons.photoScan.photos"
        static let videos = "liberons.photoScan.videos"
        static let bytes = "liberons.photoScan.bytes"
        static let total = "liberons.photoScan.total"
        static let date = "liberons.photoScan.date"
    }

    override init() {
        super.init()
        restoreCachedScan()
        PHPhotoLibrary.shared().register(self)
    }

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    var canReadLibrary: Bool { authorizationStatus == .authorized || authorizationStatus == .limited }
    var hasCompletedScan: Bool { lastScanDate != nil && totalItems > 0 }

    func requestAccessAndScan() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        guard status == .authorized || status == .limited else { return }
        refreshCountsFast()
        if !hasCompletedScan { await scan(force: true) }
    }

    func scan(force: Bool = false) async {
        guard canReadLibrary, !isScanning else { return }
        if hasCompletedScan && !libraryHasChanged && !force { return }

        isScanning = true
        errorMessage = nil
        refreshCountsFast()

        let assets = PHAsset.fetchAssets(with: nil)
        let count = assets.count
        var bytes: Int64 = 0

        // Size calculation is intentionally chunked so a very large library does not
        // monopolize the main actor and make scrolling/taps feel frozen.
        for index in 0..<count {
            if Task.isCancelled { isScanning = false; return }
            let asset = assets.object(at: index)
            for resource in PHAssetResource.assetResources(for: asset) {
                if let value = resource.value(forKey: "fileSize") as? NSNumber { bytes += value.int64Value }
            }
            if index.isMultiple(of: 40) || index == count - 1 {
                scannedItems = index + 1
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(1))
            }
        }

        estimatedBytes = bytes
        totalItems = count
        scannedItems = count
        lastScanDate = Date()
        libraryHasChanged = false
        isScanning = false
        persistScan()
    }

    func refreshIfNeeded() async {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canReadLibrary else { return }
        refreshCountsFast()
        // Keep the cached size instantly available. A Photos change no longer starts a
        // 28k-item resource scan while the user is navigating the app.
        if !hasCompletedScan { await scan(force: true) }
    }

    func scanNow() async { await scan(force: true) }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.libraryHasChanged = true
            self.refreshCountsFast()
        }
    }

    private func refreshCountsFast() {
        guard canReadLibrary else { return }
        let imageOptions = PHFetchOptions()
        imageOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let videoOptions = PHFetchOptions()
        videoOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        photoCount = PHAsset.fetchAssets(with: imageOptions).count
        videoCount = PHAsset.fetchAssets(with: videoOptions).count
        totalItems = photoCount + videoCount
    }

    var formattedSize: String { ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file) }
    var formattedLastScan: String? { lastScanDate?.formatted(date: .abbreviated, time: .shortened) }

    private func restoreCachedScan() {
        guard defaults.integer(forKey: Key.version) == cacheVersion,
              let date = defaults.object(forKey: Key.date) as? Date else { return }
        photoCount = defaults.integer(forKey: Key.photos)
        videoCount = defaults.integer(forKey: Key.videos)
        estimatedBytes = Int64(defaults.object(forKey: Key.bytes) as? NSNumber ?? 0)
        totalItems = defaults.integer(forKey: Key.total)
        scannedItems = totalItems
        lastScanDate = date
    }

    private func persistScan() {
        defaults.set(cacheVersion, forKey: Key.version)
        defaults.set(photoCount, forKey: Key.photos)
        defaults.set(videoCount, forKey: Key.videos)
        defaults.set(NSNumber(value: estimatedBytes), forKey: Key.bytes)
        defaults.set(totalItems, forKey: Key.total)
        defaults.set(lastScanDate, forKey: Key.date)
    }
}
