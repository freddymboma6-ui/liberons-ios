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

    // Keep the backend page at its supported cap, but publish the first page
    // immediately instead of draining the user's entire library before rendering.
    // Additional metadata pages are fetched only as the grid approaches the end.
    private let pageSize = 1_000
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
        // Category changes remain local for already-loaded metadata. Never throw
        // away a loaded page merely because the user taps All / Photos / Videos.
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

            // Counts and the first metadata page are independent. Fetch them in
            // parallel so the first visible gallery arrives with only one page of
            // metadata regardless of whether the account has 3 or 100,000 items.
            async let countsTask = fetchCounts()
            async let firstPageTask = fetchPage(after: nil, newestFirst: newestFirst)

            let firstPage = try await firstPageTask
            let counts = try await countsTask

            items = normalize(firstPage)
            totalCount = counts.all_count
            photoCount = counts.photo_count
            videoCount = counts.video_count
            updateCursor(from: firstPage)
            hasMore = !firstPage.isEmpty && Int64(firstPage.count) < counts.all_count
        } catch is CancellationError {
            // A cancelled refresh should not replace the current library with an error.
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
            hasMore = Int64(items.count) < totalCount && page.count == pageSize
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
        // Force a real reload after cloud data changes while preserving the user's
        // current local filter/sort state.
        items.removeAll(keepingCapacity: true)
        Task { await refresh(filter: currentFilter, newestFirst: currentNewestFirst) }
    }
}
