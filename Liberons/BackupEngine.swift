import Foundation
import Combine
import Photos
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class BackupEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var message = ""
    @Published private(set) var selectedLocalIdentifier: String?
    @Published private(set) var selectedFilename: String?
    @Published private(set) var selectedBytes: Int64 = 0
    @Published private(set) var selectedIsVideo = false
    @Published private(set) var selectedCreationDate: Date?
    @Published private(set) var lastProtectedLocalIdentifier: String?
    @Published private(set) var lastProtectedFilename: String?
    @Published private(set) var lastProtectedBytes: Int64 = 0
    @Published private(set) var lastProtectedIsVideo = false
    @Published private(set) var queueTotal = 0
    @Published private(set) var queueCompleted = 0
    @Published private(set) var queueFailed = 0
    @Published private(set) var currentQueueFilename: String?
    private var selectionConfirmed = false

    var queueProgress: Double { queueTotal == 0 ? 0 : Double(queueCompleted + queueFailed) / Double(queueTotal) }

    private struct InitiateResponse: Decodable {
        struct Upload: Decodable { let url: String; let headers: [String: String] }
        let asset_id: String; let upload_session_id: String; let upload: Upload
    }

    func prepareNewestAsset() {
        let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]; options.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: options).firstObject, let resource = PHAssetResource.assetResources(for: asset).first else { selectedLocalIdentifier = nil; selectedFilename = nil; message = "No media found"; return }
        setPreview(asset: asset, resource: resource)
        selectionConfirmed = true
        message = "Preview ready — tap again to protect"
    }

    func backupSelectedAsset() async {
        guard !isRunning else { return }
        guard let localIdentifier = selectedLocalIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject, let resource = PHAssetResource.assetResources(for: asset).first else { message = "Selected media is no longer available"; return }
        isRunning = true; defer { isRunning = false }
        do { try await protect(asset: asset, resource: resource); message = "Protected ✓" } catch { message = error.localizedDescription }
    }

    func backupOneNewestAsset() async {
        if !selectionConfirmed { prepareNewestAsset(); return }
        selectionConfirmed = false
        await backupSelectedAsset()
    }

    func backupNewestItems(count: Int) async {
        guard !isRunning, count > 0 else { return }
        let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]; options.fetchLimit = count
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []; result.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { message = "No media found"; return }
        isRunning = true; queueTotal = assets.count; queueCompleted = 0; queueFailed = 0
        defer { isRunning = false; currentQueueFilename = nil }
        for asset in assets {
            guard let resource = PHAssetResource.assetResources(for: asset).first else { queueFailed += 1; continue }
            currentQueueFilename = resource.originalFilename; setPreview(asset: asset, resource: resource)
            message = "Protecting \(queueCompleted + queueFailed + 1) of \(queueTotal)…"
            do { try await protect(asset: asset, resource: resource); queueCompleted += 1 } catch { queueFailed += 1 }
        }
        message = queueFailed == 0 ? "\(queueCompleted) items protected ✓" : "\(queueCompleted) protected • \(queueFailed) failed"
    }

    private func setPreview(asset: PHAsset, resource: PHAssetResource) {
        selectedLocalIdentifier = asset.localIdentifier; selectedFilename = resource.originalFilename; selectedIsVideo = asset.mediaType == .video; selectedCreationDate = asset.creationDate
        selectedBytes = Int64(resource.value(forKey: "fileSize") as? CLong ?? 0)
    }

    private func protect(asset: PHAsset, resource: PHAssetResource) async throws {
        var temporaryURL: URL?
        defer { if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) } }
        let ext = (resource.originalFilename as NSString).pathExtension
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext); temporaryURL = temp
        try await export(resource: resource, to: temp)
        let byteCount = (try temp.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard byteCount > 0 else { throw NSError(domain: "LiberonsBackup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Exported media is empty"]) }
        selectedBytes = Int64(byteCount)
        let checksum = try sha256(fileURL: temp)
        let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? (asset.mediaType == .video ? "video/mp4" : "image/jpeg")
        let iso = ISO8601DateFormatter(); var body: [String: Any] = ["filename": resource.originalFilename, "mime_type": mimeType, "size_bytes": byteCount, "checksum_sha256": checksum, "ios_local_identifier": asset.localIdentifier]
        if let captured = asset.creationDate { body["captured_at"] = iso.string(from: captured) }
        let initiated = try JSONDecoder().decode(InitiateResponse.self, from: SupabaseService.callFunction("initiate-upload", json: try JSONSerialization.data(withJSONObject: body)))
        guard let signedURL = URL(string: initiated.upload.url) else { throw NSError(domain: "LiberonsBackup", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid signed upload URL"]) }
        try await SupabaseService.putFile(temp, to: signedURL, headers: initiated.upload.headers)
        let verifiedData = try await SupabaseService.verifyUpload(assetID: initiated.asset_id, uploadSessionID: initiated.upload_session_id)
        let verifiedObject = try JSONSerialization.jsonObject(with: verifiedData) as? [String: Any]
        guard verifiedObject?["protected"] as? Bool == true else { throw NSError(domain: "LiberonsBackup", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cloud copy was not marked protected"]) }
        lastProtectedLocalIdentifier = asset.localIdentifier; lastProtectedFilename = resource.originalFilename; lastProtectedBytes = Int64(byteCount); lastProtectedIsVideo = asset.mediaType == .video
    }

    private func export(resource: PHAssetResource, to url: URL) async throws { try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = true; PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) } } } }
    private func sha256(fileURL: URL) throws -> String { let handle = try FileHandle(forReadingFrom: fileURL); defer { try? handle.close() }; var hasher = SHA256(); while true { let data = try handle.read(upToCount: 1_048_576) ?? Data(); if data.isEmpty { break }; hasher.update(data: data) }; return hasher.finalize().map { String(format: "%02x", $0) }.joined() }
}
