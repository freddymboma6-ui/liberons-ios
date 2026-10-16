import Foundation
import Combine
import Supabase

extension Notification.Name { static let liberonsCloudDidChange = Notification.Name("liberons.cloud.didChange") }

@MainActor
final class CloudStorageSummary: ObservableObject {
    static let freeQuotaBytes: Int64 = 2_000_000_000

    @Published private(set) var protectedBytes: Int64 = 0
    @Published private(set) var pendingBytes: Int64 = 0
    @Published private(set) var quotaBytes: Int64 = freeQuotaBytes
    @Published private(set) var protectedCount: Int = 0
    @Published private(set) var lastProtectedAt: Date?
    @Published private(set) var isLoading = false
    private var observer: NSObjectProtocol?

    private struct Usage: Decodable { let quota_bytes: Int64; let protected_bytes: Int64; let pending_bytes: Int64 }
    private struct Asset: Decodable { let protected_at: Date?; let size_bytes: Int64? }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .liberonsCloudDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var usageProtected: Int64?
        do {
            let response = try await SupabaseService.client.from("storage_usage").select("quota_bytes,protected_bytes,pending_bytes").limit(1).execute()
            if let usage = try decoder.decode([Usage].self, from: response.data).first {
                quotaBytes = usage.quota_bytes > 0 ? usage.quota_bytes : Self.freeQuotaBytes
                usageProtected = usage.protected_bytes
                pendingBytes = max(0, usage.pending_bytes)
            } else { quotaBytes = Self.freeQuotaBytes }
        } catch { if quotaBytes <= 0 { quotaBytes = Self.freeQuotaBytes } }

        do {
            let response = try await SupabaseService.client.from("media_assets").select("protected_at,size_bytes").eq("status", value: "protected").order("protected_at", ascending: false).execute()
            let assets = try decoder.decode([Asset].self, from: response.data)
            protectedCount = assets.count
            lastProtectedAt = assets.first?.protected_at
            let actualAssetBytes = assets.reduce(Int64(0)) { $0 + max(0, $1.size_bytes ?? 0) }
            protectedBytes = actualAssetBytes > 0 ? actualAssetBytes : max(0, usageProtected ?? 0)
        } catch {
            protectedBytes = max(0, usageProtected ?? protectedBytes)
        }
    }
}
