import Foundation
import Combine

@MainActor
final class ProtectedMediaStore: ObservableObject {
    @Published private(set) var items: [ProtectedCloudMedia] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await SupabaseService.client
                .from("media_assets")
                .select("id,ios_local_identifier,original_filename,media_type,size_bytes,captured_at")
                .eq("status", value: "protected")
                .order("captured_at", ascending: false)
                .execute()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([ProtectedCloudMedia].self, from: response.data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
