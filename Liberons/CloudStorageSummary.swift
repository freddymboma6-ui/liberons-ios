import Foundation
import Combine
import Supabase

@MainActor
final class CloudStorageSummary: ObservableObject {
    @Published private(set) var protectedBytes: Int64 = 0
    @Published private(set) var pendingBytes: Int64 = 0
    @Published private(set) var quotaBytes: Int64 = 0
    @Published private(set) var protectedCount: Int = 0
    @Published private(set) var lastProtectedAt: Date?
    @Published private(set) var isLoading = false

    private struct Usage: Decodable {
        let quota_bytes: Int64
        let protected_bytes: Int64
        let pending_bytes: Int64
    }

    private struct Asset: Decodable {
        let protected_at: Date?
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let usageResponse = try await SupabaseService.client
                .from("storage_usage")
                .select("quota_bytes,protected_bytes,pending_bytes")
                .limit(1)
                .execute()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let usage = try decoder.decode([Usage].self, from: usageResponse.data).first {
                quotaBytes = usage.quota_bytes
                protectedBytes = usage.protected_bytes
                pendingBytes = usage.pending_bytes
            }

            let assetsResponse = try await SupabaseService.client
                .from("media_assets")
                .select("protected_at")
                .eq("status", value: "protected")
                .order("protected_at", ascending: false)
                .execute()
            let assets = try decoder.decode([Asset].self, from: assetsResponse.data)
            protectedCount = assets.count
            lastProtectedAt = assets.first?.protected_at
        } catch {
            // Dashboard remains usable with zero values if cloud state cannot be read.
        }
    }
}
