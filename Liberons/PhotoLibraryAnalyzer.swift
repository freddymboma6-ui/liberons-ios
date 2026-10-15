import Foundation
import Photos
import Combine

@MainActor
final class PhotoLibraryAnalyzer: ObservableObject {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var photoCount = 0
    @Published private(set) var videoCount = 0
    @Published private(set) var estimatedBytes: Int64 = 0
    @Published private(set) var scannedItems = 0
    @Published private(set) var totalItems = 0
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?

    var canReadLibrary: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    func requestAccessAndScan() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        guard status == .authorized || status == .limited else { return }
        await scan()
    }

    func scan() async {
        guard canReadLibrary else { return }
        isScanning = true
        errorMessage = nil
        photoCount = 0
        videoCount = 0
        estimatedBytes = 0
        scannedItems = 0

        let assets = PHAsset.fetchAssets(with: nil)
        totalItems = assets.count
        var bytes: Int64 = 0
        var photos = 0
        var videos = 0

        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            switch asset.mediaType {
            case .image: photos += 1
            case .video: videos += 1
            default: break
            }

            let resources = PHAssetResource.assetResources(for: asset)
            for resource in resources {
                if let value = resource.value(forKey: "fileSize") as? NSNumber {
                    bytes += value.int64Value
                }
            }

            if index.isMultiple(of: 100) || index == assets.count - 1 {
                photoCount = photos
                videoCount = videos
                estimatedBytes = bytes
                scannedItems = index + 1
                await Task.yield()
            }
        }

        photoCount = photos
        videoCount = videos
        estimatedBytes = bytes
        scannedItems = assets.count
        isScanning = false
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file)
    }
}
