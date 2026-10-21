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
        // Every caller awaits the same real refresh. Explicitly returning Void keeps
        // this task typed as Task<Void, Never> even though self is captured weakly.
        if let activeRefresh {
            await activeRefresh.value
            return
        }

        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh()
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

            // A local Photos identifier can legitimately be present on more than one
            // historical cloud row. Keep every protected cloud item, but expose the
            // PhotoKit identifier only once so consumers can safely build identifier
            // lookups without Dictionary(uniqueKeysWithValues:) trapping at runtime.
            var seenLocalIdentifiers = Set<String>()
            items = allItems.map { item in
                guard let localIdentifier = item.iosLocalIdentifier,
                      !localIdentifier.isEmpty else { return item }

                guard seenLocalIdentifiers.insert(localIdentifier).inserted else {
                    return ProtectedCloudMedia(
                        id: item.id,
                        iosLocalIdentifier: nil,
                        originalFilename: item.originalFilename,
                        mediaType: item.mediaType,
                        sizeBytes: item.sizeBytes,
                        capturedAt: item.capturedAt,
                        protectedAt: item.protectedAt,
                        createdAt: item.createdAt,
                        localRemovedAt: item.localRemovedAt
                    )
                }
                return item
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAfterProtection() { Task { await refresh() } }
}
