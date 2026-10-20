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
    private var pullToRefreshObserver: NSObjectProtocol?
    private enum Key { static let version="liberons.photoScan.version"; static let photos="liberons.photoScan.photos"; static let videos="liberons.photoScan.videos"; static let bytes="liberons.photoScan.bytes"; static let total="liberons.photoScan.total"; static let date="liberons.photoScan.date" }

    override init() {
        super.init()
        restoreCachedScan()
        PHPhotoLibrary.shared().register(self)
        pullToRefreshObserver = NotificationCenter.default.addObserver(forName: .liberonsPullToRefresh, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshDashboardFast()
            }
        }
    }
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        if let pullToRefreshObserver { NotificationCenter.default.removeObserver(pullToRefreshObserver) }
    }
    var canReadLibrary: Bool { authorizationStatus == .authorized || authorizationStatus == .limited }
    var hasCompletedScan: Bool { lastScanDate != nil && totalItems > 0 }

    func requestAccessAndScan() async { authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite); guard canReadLibrary else { return }; refreshCountsFast(); if !hasCompletedScan { await scan(force: true) } }

    func scan(force: Bool = false) async {
        guard canReadLibrary, !isScanning else { return }
        if hasCompletedScan && !libraryHasChanged && !force { return }
        isScanning = true; errorMessage = nil; refreshCountsFast(); scannedItems = 0
        let expectedTotal = totalItems
        let result = await Task.detached(priority: .utility) { () -> (Int64, Int) in
            let assets = PHAsset.fetchAssets(with: nil)
            var bytes: Int64 = 0
            autoreleasepool {
                for index in 0..<assets.count {
                    let asset = assets.object(at: index)
                    for resource in PHAssetResource.assetResources(for: asset) {
                        if let value = resource.value(forKey: "fileSize") as? NSNumber { bytes += value.int64Value }
                    }
                }
            }
            return (bytes, assets.count)
        }.value
        estimatedBytes = result.0; totalItems = result.1; scannedItems = result.1; lastScanDate = Date(); libraryHasChanged = false; isScanning = false; persistScan()
        if expectedTotal != result.1 { refreshCountsFast() }
    }

    func refreshIfNeeded() async { authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite); guard canReadLibrary else { return }; refreshCountsFast(); if !hasCompletedScan { await scan(force: true) } }
    func refreshDashboardFast() async { authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite); guard canReadLibrary else { return }; refreshCountsFast(); persistCountsOnly(); await Task.yield() }
    func scanNow() async { await scan(force: true) }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) { Task { @MainActor [weak self] in guard let self else { return }; self.libraryHasChanged = true; self.refreshCountsFast(); self.persistCountsOnly() } }

    private func refreshCountsFast() { guard canReadLibrary else { return }; let imageOptions=PHFetchOptions(); imageOptions.predicate=NSPredicate(format:"mediaType == %d",PHAssetMediaType.image.rawValue); let videoOptions=PHFetchOptions(); videoOptions.predicate=NSPredicate(format:"mediaType == %d",PHAssetMediaType.video.rawValue); photoCount=PHAsset.fetchAssets(with:imageOptions).count; videoCount=PHAsset.fetchAssets(with:videoOptions).count; totalItems=photoCount+videoCount }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file) }
    var formattedLastScan: String? { lastScanDate?.formatted(date:.abbreviated,time:.shortened) }
    private func restoreCachedScan() { guard defaults.integer(forKey:Key.version)==cacheVersion, let date=defaults.object(forKey:Key.date) as? Date else{return}; photoCount=defaults.integer(forKey:Key.photos);videoCount=defaults.integer(forKey:Key.videos);estimatedBytes=Int64(defaults.object(forKey:Key.bytes) as? NSNumber ?? 0);totalItems=defaults.integer(forKey:Key.total);scannedItems=totalItems;lastScanDate=date }
    private func persistCountsOnly(){guard lastScanDate != nil else{return};defaults.set(cacheVersion,forKey:Key.version);defaults.set(photoCount,forKey:Key.photos);defaults.set(videoCount,forKey:Key.videos);defaults.set(totalItems,forKey:Key.total)}
    private func persistScan(){defaults.set(cacheVersion,forKey:Key.version);defaults.set(photoCount,forKey:Key.photos);defaults.set(videoCount,forKey:Key.videos);defaults.set(NSNumber(value:estimatedBytes),forKey:Key.bytes);defaults.set(totalItems,forKey:Key.total);defaults.set(lastScanDate,forKey:Key.date)}
}
