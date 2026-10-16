import Foundation
import Combine
import Photos
import Supabase

@MainActor
final class ProtectedSpaceCleaner: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isDeleting = false
    @Published private(set) var protectedLocalIdentifiers: [String] = []
    @Published private(set) var selectedLocalIdentifiers: [String] = []
    @Published private(set) var selectedBytes: Int64 = 0
    @Published private(set) var message = ""

    private struct ProtectedRow: Decodable {
        let id: UUID
        let iosLocalIdentifier: String?
        let originalFilename: String?
        let capturedAt: Date?
        let sizeBytes: Int64?
        enum CodingKeys: String, CodingKey {
            case id
            case iosLocalIdentifier = "ios_local_identifier"
            case originalFilename = "original_filename"
            case capturedAt = "captured_at"
            case sizeBytes = "size_bytes"
        }
    }

    private func localAsset(for row: ProtectedRow) -> PHAsset? {
        if let identifier = row.iosLocalIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
            return asset
        }

        let options = PHFetchOptions()
        if let capturedAt = row.capturedAt {
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                capturedAt.addingTimeInterval(-2) as NSDate,
                capturedAt.addingTimeInterval(2) as NSDate
            )
        }
        let result = PHAsset.fetchAssets(with: options)
        guard result.count > 0 else { return nil }

        if let filename = row.originalFilename {
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

    func prepare(removalPercent: Int) async {
        guard !isLoading && !isDeleting else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await SupabaseService.client
                .from("media_assets")
                .select("id,ios_local_identifier,original_filename,captured_at,size_bytes")
                .eq("status", value: "protected")
                .order("captured_at", ascending: true)
                .execute()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let rows = try decoder.decode([ProtectedRow].self, from: response.data)

            var resolved: [(row: ProtectedRow, asset: PHAsset)] = []
            for row in rows {
                guard let asset = localAsset(for: row) else { continue }
                resolved.append((row, asset))
                if row.iosLocalIdentifier != asset.localIdentifier {
                    try? await SupabaseService.updateLocalIdentifier(assetID: row.id, localIdentifier: asset.localIdentifier)
                }
            }

            protectedLocalIdentifiers = resolved.map { $0.asset.localIdentifier }
            let requested = resolved.isEmpty ? 0 : max(1, Int((Double(resolved.count) * Double(removalPercent) / 100.0).rounded()))
            let selected = Array(resolved.prefix(min(requested, resolved.count)))
            selectedLocalIdentifiers = selected.map { $0.asset.localIdentifier }
            selectedBytes = selected.reduce(Int64(0)) { $0 + max(0, $1.row.sizeBytes ?? 0) }

            if selected.isEmpty {
                message = "Aucun original protégé et vérifié n’est actuellement présent sur cet iPhone."
            } else {
                let size = ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)
                message = "\(selected.count) élément(s) • environ \(size) peuvent être libérés."
            }
        } catch {
            selectedLocalIdentifiers = []
            selectedBytes = 0
            message = error.localizedDescription
        }
    }

    func deletePreparedFromIPhone() async {
        guard !isDeleting, !selectedLocalIdentifiers.isEmpty else { return }
        isDeleting = true
        defer { isDeleting = false }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: selectedLocalIdentifiers, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else {
            message = "Aucun original sélectionné n’est encore présent sur cet iPhone."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            let removed = assets.count
            protectedLocalIdentifiers.removeAll { selectedLocalIdentifiers.contains($0) }
            selectedLocalIdentifiers = []
            selectedBytes = 0
            message = "\(removed) original(aux) retiré(s) de cet iPhone. Les copies Libérons restent protégées."
        } catch {
            message = error.localizedDescription
        }
    }
}
