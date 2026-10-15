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
    @Published private(set) var message = ""

    private struct ProtectedRow: Decodable {
        let iosLocalIdentifier: String?
        enum CodingKeys: String, CodingKey { case iosLocalIdentifier = "ios_local_identifier" }
    }

    func prepare(removalPercent: Int) async {
        guard !isLoading && !isDeleting else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await SupabaseService.client
                .from("media_assets")
                .select("ios_local_identifier")
                .eq("status", value: "protected")
                .order("captured_at", ascending: true)
                .execute()
            let rows = try JSONDecoder().decode([ProtectedRow].self, from: response.data)
            let ids = rows.compactMap(\.iosLocalIdentifier).filter {
                PHAsset.fetchAssets(withLocalIdentifiers: [$0], options: nil).firstObject != nil
            }
            protectedLocalIdentifiers = ids
            let requested = ids.isEmpty ? 0 : max(1, Int((Double(ids.count) * Double(removalPercent) / 100.0).rounded()))
            selectedLocalIdentifiers = Array(ids.prefix(min(requested, ids.count)))
            message = selectedLocalIdentifiers.isEmpty
                ? "No protected originals are currently available on this iPhone."
                : "\(selectedLocalIdentifiers.count) protected originals ready for local removal."
        } catch {
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
            message = "Nothing to remove from this iPhone."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            let removed = assets.count
            protectedLocalIdentifiers.removeAll { selectedLocalIdentifiers.contains($0) }
            selectedLocalIdentifiers = []
            message = "\(removed) local originals removed. Cloud copies remain protected."
        } catch {
            message = error.localizedDescription
        }
    }
}
