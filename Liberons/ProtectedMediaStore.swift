import Foundation
import Combine
import Supabase

@MainActor
final class ProtectedMediaStore: ObservableObject {
    @Published private(set) var items: [ProtectedCloudMedia] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var totalCount: Int64 = 0
    @Published private(set) var photoCount: Int64 = 0
    @Published private(set) var videoCount: Int64 = 0

    // Keep the complete protected-media metadata window in memory. Thumbnails and
    // originals remain lazy, so switching All / Photos / Videos is purely local.
    private let pageSize = 20_000
    private var activeRefresh: Task<Void, Never>?
    private var activeLoadMore: Task<Void, Never>?
    private var cursor: Cursor?
    private var currentFilter = "all"
    private var currentNewestFirst = true
    private var seenLocalIdentifiers = Set<String>()

    private struct Cursor: Equatable { let sortDate: Date; let id: UUID }
    private struct PageParams: Encodable { let p_cursor_at: String?; let p_cursor_id: String?; let p_limit: Int; let p_media_kind: String; let p_newest_first: Bool }
    private struct CountsRow: Decodable { let all_count: Int64; let photo_count: Int64; let video_count: Int64 }

    func refresh(filter: String = "all", newestFirst: Bool = true) async {
        // The view already filters/sorts store.items locally. Once the complete
        // metadata set is loaded, a category/sort tap must never make a network
        // round-trip. This is what makes the segmented control instant.
        if !items.isEmpty && (filter != currentFilter || newestFirst != currentNewestFirst) {
            currentFilter = filter
            currentNewestFirst = newestFirst
            return
        }

        if let activeRefresh { await activeRefresh.value; return }
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(requestedFilter: filter, newestFirst: newestFirst)
        }
        activeRefresh = task
        await task.value
        activeRefresh = nil
    }

    func loadMoreIfNeeded(currentItem item: ProtectedCloudMedia) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        let threshold = max(items.count - 30, 0)
        guard let index = items.firstIndex(where: { $0.id == item.id }), index >= threshold else { return }
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        if let activeLoadMore { await activeLoadMore.value; return }
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoadMore()
        }
        activeLoadMore = task
        await task.value
        activeLoadMore = nil
    }

    private func performRefresh(requestedFilter: String, newestFirst: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            currentFilter = requestedFilter
            currentNewestFirst = newestFirst
            cursor = nil
            hasMore = true
            seenLocalIdentifiers.removeAll(keepingCapacity: true)

            // Always fetch ALL photo/video metadata. Filtering is local afterwards.
            // This also means "Select all" can select the real complete category,
            // instead of only the server's first page.
            async let pageTask = fetchPage(after: nil, newestFirst: newestFirst)
            async let countsTask = fetchCounts()
            let (page, counts) = try await (pageTask, countsTask)

            items = normalize(page)
            totalCount = counts.all_count
            photoCount = counts.photo_count
            videoCount = counts.video_count
            updateCursor(from: page)
            hasMore = page.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performLoadMore() async {
        guard hasMore, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await fetchPage(after: cursor, newestFirst: currentNewestFirst)
            guard !page.isEmpty else { hasMore = false; return }
            let existing = Set(items.map(\.id))
            let unique = page.filter { !existing.contains($0.id) }
            items.append(contentsOf: normalize(unique))
            updateCursor(from: page)
            hasMore = page.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchPage(after cursor: Cursor?, newestFirst: Bool) async throws -> [ProtectedCloudMedia] {
        let params = PageParams(
            p_cursor_at: cursor.map { Self.cursorFormatter.string(from: $0.sortDate) },
            p_cursor_id: cursor?.id.uuidString,
            p_limit: pageSize,
            p_media_kind: "all",
            p_newest_first: newestFirst
        )
        let response = try await SupabaseService.client.rpc("protected_media_page", params: params).execute()
        return try Self.makeDecoder().decode([ProtectedCloudMedia].self, from: response.data)
    }

    private func fetchCounts() async throws -> CountsRow {
        let response = try await SupabaseService.client.rpc("protected_media_counts").execute()
        let rows = try JSONDecoder().decode([CountsRow].self, from: response.data)
        return rows.first ?? CountsRow(all_count: 0, photo_count: 0, video_count: 0)
    }

    private func updateCursor(from page: [ProtectedCloudMedia]) {
        guard let last = page.last else { return }
        cursor = Cursor(sortDate: last.capturedAt ?? last.createdAt, id: last.id)
    }

    private func normalize(_ page: [ProtectedCloudMedia]) -> [ProtectedCloudMedia] {
        page.map { item in
            guard let localIdentifier = item.iosLocalIdentifier, !localIdentifier.isEmpty else { return item }
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
    }

    private static let cursorFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 timestamp: \(raw)")
        }
        return decoder
    }

    func refreshAfterProtection() {
        // A real data change must bypass the filter fast path. Re-fetching with the
        // same state does that while still loading the complete "all" dataset.
        Task { await refresh(filter: currentFilter, newestFirst: currentNewestFirst) }
    }
}
