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
    @Published private(set) var accountRole: String = "user"
    @Published private(set) var subscriptionStatus: String = "free"
    @Published private(set) var gracePeriodEnd: Date?
    @Published private(set) var lastPaymentFailedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var planLoadFailed = false
    var isOwner: Bool { accountRole.lowercased() == "owner" }
    var isPaymentGrace: Bool { ["past_due","grace","unpaid"].contains(subscriptionStatus) && (gracePeriodEnd.map { Date() < $0 } ?? false) }
    var isPaymentRestricted: Bool { ["past_due","grace","unpaid","restricted"].contains(subscriptionStatus) && (gracePeriodEnd.map { Date() >= $0 } ?? subscriptionStatus == "restricted") }
    var graceDaysRemaining: Int { guard let end = gracePeriodEnd, end > Date() else { return 0 }; return max(1, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 1) }
    private var observer: NSObjectProtocol?

    private struct Subscription: Decodable { let status: String?; let grace_period_end: Date?; let last_payment_failed_at: Date? }
    private struct ServerPlan: Decodable {
        let user_id: String; let quota_bytes: Int64; let protected_bytes: Int64; let pending_bytes: Int64; let role: String; let source: String; let subscription: Subscription?
    }
    private struct Asset: Decodable { let protected_at: Date?; let size_bytes: Int64? }

    init() { observer = NotificationCenter.default.addObserver(forName: .liberonsCloudDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.refresh() } } }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func refresh() async {
        guard !isLoading else { return }; isLoading = true; defer { isLoading = false }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let session = try? await SupabaseService.client.auth.session else { planLoadFailed = true; return }
        let userID = session.user.id.uuidString
        do {
            let plan: ServerPlan = try await SupabaseService.client.functions.invoke("account-storage-plan", options: FunctionInvokeOptions(headers: ["Authorization": "Bearer \(session.accessToken)"]), decode: { data, _ in try decoder.decode(ServerPlan.self, from: data) })
            guard plan.user_id.lowercased() == userID.lowercased(), plan.source == "server", plan.quota_bytes > 0 else { throw NSError(domain: "LiberonsPlan", code: 1) }
            quotaBytes = plan.quota_bytes; protectedBytes = max(0, plan.protected_bytes); pendingBytes = max(0, plan.pending_bytes); accountRole = plan.role.lowercased()
            subscriptionStatus = plan.subscription?.status?.lowercased() ?? "free"; gracePeriodEnd = plan.subscription?.grace_period_end; lastPaymentFailedAt = plan.subscription?.last_payment_failed_at; planLoadFailed = false
        } catch { planLoadFailed = true }
        do {
            let response = try await SupabaseService.client.from("media_assets").select("protected_at,size_bytes").eq("user_id", value: userID).eq("status", value: "protected").order("protected_at", ascending: false).execute()
            let assets = try decoder.decode([Asset].self, from: response.data); protectedCount = assets.count; lastProtectedAt = assets.first?.protected_at
            let actualAssetBytes = assets.reduce(Int64(0)) { $0 + max(0, $1.size_bytes ?? 0) }; if actualAssetBytes > 0 { protectedBytes = actualAssetBytes }
        } catch { }
    }
}
