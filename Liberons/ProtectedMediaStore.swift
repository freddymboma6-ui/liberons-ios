import Foundation
import Combine
import Supabase

@MainActor
final class ProtectedMediaStore: ObservableObject {
    @Published private(set) var items: [ProtectedCloudMedia] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let pageSize = 1000
    private var activeRefresh: Task<Void, Never>?

    func refresh() async {
        // Every caller awaits the same real refresh. This is important for SwiftUI's
        // native pull-to-refresh: the spinner remains active until the network reload
        // has actually completed instead of ending when another refresh is in flight.
        if let activeRefresh {
            await activeRefresh.value
            return
        }

        let task = Task { @MainActor [weak self] in
            await self?.performRefresh()
        }
        activeRefresh = task
        await task.value
        activeRefresh = nil
    }

    private func performRefresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var allItems: [ProtectedCloudMedia] = []
            var offset = 0

            while true {
                let response = try await SupabaseService.client
                    .from("media_assets")
                    .select("id,ios_local_identifier,original_filename,media_type,size_bytes,captured_at,protected_at,created_at,local_removed_at")
                    .eq("status", value: "protected")
                    .order("captured_at", ascending: false)
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()

                let page = try decoder.decode([ProtectedCloudMedia].self, from: response.data)
                allItems.append(contentsOf: page)

                if page.count < pageSize { break }
                offset += pageSize
            }

            items = allItems
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAfterProtection() { Task { await refresh() } }
}
