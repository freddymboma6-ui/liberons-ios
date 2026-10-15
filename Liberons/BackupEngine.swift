import Foundation
import Photos
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class BackupEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var message = ""

    private struct InitiateResponse: Decodable {
        struct Upload: Decodable {
            let url: String
            let headers: [String: String]
        }
        let asset_id: String
        let upload_session_id: String
        let upload: Upload
    }

    func backupOneNewestAsset() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var temporaryURL: URL?
        do {
            message = "Preparing media…"
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 1
            guard let asset = PHAsset.fetchAssets(with: options).firstObject else {
                throw NSError(domain: "LiberonsBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: "No media found"])
            }
            guard let resource = PHAssetResource.assetResources(for: asset).first else {
                throw NSError(domain: "LiberonsBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: "No media resource found"])
            }

            let ext = (resource.originalFilename as NSString).pathExtension
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            temporaryURL = temp

            try await export(resource: resource, to: temp)
            let values = try temp.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = values.fileSize ?? 0
            guard byteCount > 0 else {
                throw NSError(domain: "LiberonsBackup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Exported media is empty"])
            }

            message = "Securing media…"
            let checksum = try sha256(fileURL: temp)
            let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? (asset.mediaType == .video ? "video/mp4" : "image/jpeg")
            let iso = ISO8601DateFormatter()
            var body: [String: Any] = [
                "filename": resource.originalFilename,
                "mime_type": mimeType,
                "size_bytes": byteCount,
                "checksum_sha256": checksum,
                "ios_local_identifier": asset.localIdentifier
            ]
            if let captured = asset.creationDate { body["captured_at"] = iso.string(from: captured) }

            let requestData = try JSONSerialization.data(withJSONObject: body)
            let initiateData = try await SupabaseService.callFunction("initiate-upload", json: requestData)
            let initiated = try JSONDecoder().decode(InitiateResponse.self, from: initiateData)
            guard let signedURL = URL(string: initiated.upload.url) else {
                throw NSError(domain: "LiberonsBackup", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid signed upload URL"])
            }

            message = "Uploading…"
            try await SupabaseService.putFile(temp, to: signedURL, headers: initiated.upload.headers)

            message = "Verifying…"
            let verifiedData = try await SupabaseService.verifyUpload(assetID: initiated.asset_id, uploadSessionID: initiated.upload_session_id)
            let verifiedObject = try JSONSerialization.jsonObject(with: verifiedData) as? [String: Any]
            guard verifiedObject?["protected"] as? Bool == true else {
                throw NSError(domain: "LiberonsBackup", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cloud copy was not marked protected"])
            }
            message = "Protected ✓"
        } catch {
            message = error.localizedDescription
        }
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
    }

    private func export(resource: PHAssetResource, to url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func sha256(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
