import Foundation
import Photos

struct ProtectedBulkRestoreResult: Sendable {
    let restored: Int
    let alreadyAvailable: Int
    let failed: Int
}

enum ProtectedBulkRestoreService {
    private static func isVideo(_ item: ProtectedCloudMedia) -> Bool {
        item.mediaType.lowercased().contains("video")
    }

    @MainActor
    private static func matchingLocalAsset(for item: ProtectedCloudMedia) -> PHAsset? {
        if let identifier = item.iosLocalIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
            return asset
        }

        let options = PHFetchOptions()
        if let date = item.capturedAt {
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                date.addingTimeInterval(-2) as NSDate,
                date.addingTimeInterval(2) as NSDate
            )
        }
        let result = PHAsset.fetchAssets(with: isVideo(item) ? .video : .image, options: options)
        guard result.count > 0 else { return nil }

        if let filename = item.originalFilename {
            var match: PHAsset?
            result.enumerateObjects { asset, _, stop in
                if PHAssetResource.assetResources(for: asset).contains(where: {
                    $0.originalFilename.caseInsensitiveCompare(filename) == .orderedSame
                }) {
                    match = asset
                    stop.pointee = true
                }
            }
            if let match { return match }
        }
        return result.firstObject
    }

    static func restoreMissing(_ items: [ProtectedCloudMedia]) async -> ProtectedBulkRestoreResult {
        var restored = 0
        var alreadyAvailable = 0
        var failed = 0

        for item in items {
            if await MainActor.run(body: { matchingLocalAsset(for: item) != nil }) {
                alreadyAvailable += 1
                continue
            }

            do {
                let video = isVideo(item)
                let remote = try await SupabaseService.cloudOriginalURL(assetID: item.id)
                let ext = item.originalFilename.flatMap {
                    let value = URL(fileURLWithPath: $0).pathExtension
                    return value.isEmpty ? nil : value
                } ?? (video ? "mov" : "jpg")

                let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("LiberonsBulkRecovery", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let local = directory.appendingPathComponent(item.id.uuidString).appendingPathExtension(ext)

                if !FileManager.default.fileExists(atPath: local.path) {
                    let (downloaded, response) = try await URLSession.shared.download(from: remote)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
                    }
                    try? FileManager.default.removeItem(at: local)
                    try FileManager.default.moveItem(at: downloaded, to: local)
                }

                var newIdentifier: String?
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = item.capturedAt
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = item.originalFilename
                    request.addResource(with: video ? .video : .photo, fileURL: local, options: options)
                    newIdentifier = request.placeholderForCreatedAsset?.localIdentifier
                }

                guard let newIdentifier else { throw NSError(domain: "LiberonsBulkRestore", code: 2) }
                try? await SupabaseService.updateLocalIdentifier(assetID: item.id, localIdentifier: newIdentifier)
                try? FileManager.default.removeItem(at: local)
                restored += 1
            } catch {
                failed += 1
            }
        }

        return ProtectedBulkRestoreResult(restored: restored, alreadyAvailable: alreadyAvailable, failed: failed)
    }
}
