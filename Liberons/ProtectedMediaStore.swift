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
            let userID = try await SupabaseService.client.auth.session.user.id
            let decoder = Self.makeDecoder()
            var allItems: [ProtectedCloudMedia] = []
            var offset = 0

            while true {
                let response = try await SupabaseService.client
                    .from("media_assets")
                    .select("id,ios_local_identifier,original_filename,media_type,size_bytes,captured_at,protected_at,created_at,local_removed_at")
                    .eq("user_id", value: userID.uuidString)
                    .eq("status", value: "protected")
                    .order("captured_at", ascending: false)
                    .order("created_at", ascending: false)
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()

                let page = try decoder.decode([ProtectedCloudMedia].self, from: response.data)
                allItems.append(contentsOf: page)

                if page.count < pageSize { break }
                offset += pageSize
            }

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

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 timestamp: \(raw)"
            )
        }
        return decoder
    }

    func refreshAfterProtection() { Task { await refresh() } }
}
