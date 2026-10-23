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

    // Keep the initial payload deliberately small. A customer may have hundreds of
    // thousands (or millions) of cloud memories; the device must never materialize
    // the whole library just to open the screen.
    private let pageSize = 180
    private var activeRefresh: Task<Void, Never>?
    private var activeLoadMore: Task<Void, Never>?
    private var userID: UUID?
    private var cursor: Cursor?

    private struct Cursor: Equatable {
        let capturedAt: Date
        let id: UUID
    }

    func refresh() async {
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

    func loadMoreIfNeeded(currentItem item: ProtectedCloudMedia) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        // Prefetch before the user reaches the end so scrolling remains continuous.
        let threshold = max(items.count - 36, 0)
        guard let index = items.firstIndex(where: { $0.id == item.id }), index >= threshold else { return }
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        if let activeLoadMore {
            await activeLoadMore.value
            return
        }
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoadMore()
        }
        activeLoadMore = task
        await task.value
        activeLoadMore = nil
    }

    private func performRefresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            userID = try await SupabaseService.client.auth.session.user.id
            cursor = nil
            hasMore = true
            let page = try await fetchPage(after: nil)
            items = normalize(page)
            updateCursor(from: page)
            hasMore = page.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performLoadMore() async {
        guard let cursor, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetchPage(after: cursor)
            guard !page.isEmpty else { hasMore = false; return }

            // Cursor pagination should already make pages disjoint. Keep this cheap
            // ID guard as protection against a row changing while the user scrolls.
            let existing = Set(items.map(\.id))
            let unique = page.filter { !existing.contains($0.id) }
            items.append(contentsOf: normalize(unique, preserving: items))
            updateCursor(from: page)
            hasMore = page.count == pageSize
        } catch {
            // Keep already loaded memories visible. A transient page failure should
            // never blank a large library; retry occurs when the user scrolls again.
            errorMessage = error.localizedDescription
        }
    }

    private func fetchPage(after cursor: Cursor?) async throws -> [ProtectedCloudMedia] {
        let resolvedUserID: UUID
        if let userID { resolvedUserID = userID }
        else {
            resolvedUserID = try await SupabaseService.client.auth.session.user.id
            userID = resolvedUserID
        }

        var query = SupabaseService.client
            .from("media_assets")
            .select("id,ios_local_identifier,original_filename,media_type,size_bytes,captured_at,protected_at,created_at,local_removed_at")
            .eq("user_id", value: resolvedUserID.uuidString)
            .eq("status", value: "protected")

        if let cursor {
            let date = Self.cursorFormatter.string(from: cursor.capturedAt)
            // Stable keyset cursor: (captured_at DESC, id DESC). This avoids OFFSET,
            // whose cost grows with page depth, and prevents equal timestamps from
            // being skipped between pages.
            query = query.or("captured_at.lt.\(date),and(captured_at.eq.\(date),id.lt.\(cursor.id.uuidString))")
        }

        let response = try await query
            .order("captured_at", ascending: false, nullsFirst: false)
            .order("id", ascending: false)
            .limit(pageSize)
            .execute()

        return try Self.makeDecoder().decode([ProtectedCloudMedia].self, from: response.data)
    }

    private func updateCursor(from page: [ProtectedCloudMedia]) {
        guard let last = page.last else { return }
        // Production protected rows have captured_at populated. Fall back to createdAt
        // defensively so one malformed legacy record cannot crash the library.
        cursor = Cursor(capturedAt: last.capturedAt ?? last.createdAt, id: last.id)
    }

    private func normalize(_ page: [ProtectedCloudMedia], preserving previous: [ProtectedCloudMedia] = []) -> [ProtectedCloudMedia] {
        var seen = Set(previous.compactMap(\.iosLocalIdentifier))
        return page.map { item in
            guard let localIdentifier = item.iosLocalIdentifier, !localIdentifier.isEmpty else { return item }
            guard seen.insert(localIdentifier).inserted else {
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

    func refreshAfterProtection() { Task { await refresh() } }
}
