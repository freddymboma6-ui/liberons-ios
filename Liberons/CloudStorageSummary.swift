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
    @Published private(set) var billedPlanCode: String = "free"
    @Published private(set) var billedPlanQuotaBytes: Int64 = freeQuotaBytes
    @Published private(set) var billedPlanPriceCents: Int = 0
    @Published private(set) var billedPlanCurrency: String = "USD"
    @Published private(set) var protectedCount: Int = 0
    @Published private(set) var lastProtectedAt: Date?
    @Published private(set) var accountRole: String = "user"
    @Published private(set) var subscriptionStatus: String = "free"
    @Published private(set) var gracePeriodEnd: Date?
    @Published private(set) var lastPaymentFailedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var planLoadFailed = false

    var grantedBonusBytes: Int64 { max(0, quotaBytes - billedPlanQuotaBytes) }
    var hasGrantedBonus: Bool { grantedBonusBytes > 50_000_000 }
    var isOwner: Bool { accountRole.lowercased() == "owner" }
    var isPaymentGrace: Bool { let statuses=["past_due","grace","unpaid"]; guard statuses.contains(subscriptionStatus),let end=gracePeriodEnd else{return false};return Date()<end }
    var isPaymentRestricted: Bool { if subscriptionStatus=="restricted"{return true};let statuses=["past_due","grace","unpaid"];guard statuses.contains(subscriptionStatus),let end=gracePeriodEnd else{return false};return Date()>=end }
    var graceDaysRemaining: Int { guard let end=gracePeriodEnd,end>Date() else{return 0};return max(1,Calendar.current.dateComponents([.day],from:Date(),to:end).day ?? 1) }

    private var observer:NSObjectProtocol?
    private var changeRefreshTask: Task<Void, Never>?
    private struct Subscription: Decodable { let status:String?;let grace_period_end:Date?;let last_payment_failed_at:Date? }
    private struct ServerPlan: Decodable { let user_id:String;let quota_bytes:Int64;let protected_bytes:Int64;let pending_bytes:Int64;let role:String;let source:String;let subscription:Subscription? }
    private struct StorageQuota: Decodable { let quota_bytes:Int64 }
    private struct UserSubscription: Decodable { let plan_code:String?;let status:String? }
    private struct PublicPlan: Decodable { let code:String;let quota_bytes:Int64;let monthly_price_cents:Int;let currency:String }
    private struct Asset: Decodable { let protected_at:Date?;let size_bytes:Int64? }

    init(){
        // Do not poll Supabase. A 20-second timer used to reload every protected asset,
        // subscription and quota continuously, producing thousands of unnecessary reads.
        // Cloud mutations already emit liberonsCloudDidChange; coalesce bursts (for example
        // a large backup) into one refresh after activity settles.
        observer=NotificationCenter.default.addObserver(forName:.liberonsCloudDidChange,object:nil,queue:.main){[weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleChangeRefresh() }
        }
    }
    deinit{if let observer{NotificationCenter.default.removeObserver(observer)};changeRefreshTask?.cancel()}

    private func scheduleChangeRefresh() {
        changeRefreshTask?.cancel()
        changeRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        guard !isLoading else{return};isLoading=true;defer{isLoading=false}
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        guard let session=try? await SupabaseService.client.auth.session else{planLoadFailed=true;return}
        let userID=session.user.id.uuidString

        var nextQuotaBytes=quotaBytes
        var nextAccountRole=accountRole
        var nextSubscriptionStatus=subscriptionStatus
        var nextGracePeriodEnd=gracePeriodEnd
        var nextLastPaymentFailedAt=lastPaymentFailedAt
        var nextBilledPlanCode="free"
        var nextBilledPlanQuotaBytes=Self.freeQuotaBytes
        var nextBilledPlanPriceCents=0
        var nextBilledPlanCurrency="USD"
        var nextProtectedCount=protectedCount
        var nextLastProtectedAt=lastProtectedAt
        var nextProtectedBytes=protectedBytes
        var nextPendingBytes=pendingBytes
        var receivedPlan=false

        do {
            let plan:ServerPlan=try await SupabaseService.client.functions.invoke("account-storage-plan",options:FunctionInvokeOptions(headers:["Authorization":"Bearer \(session.accessToken)"]),decode:{data,_ in try decoder.decode(ServerPlan.self,from:data)})
            guard plan.user_id.lowercased()==userID.lowercased(),plan.source=="server" else{throw NSError(domain:"LiberonsPlan",code:1)}
            nextQuotaBytes=max(0,plan.quota_bytes)
            nextAccountRole=plan.role.lowercased()
            nextSubscriptionStatus=plan.subscription?.status?.lowercased() ?? "free"
            nextGracePeriodEnd=plan.subscription?.grace_period_end
            nextLastPaymentFailedAt=plan.subscription?.last_payment_failed_at
            nextProtectedBytes=max(0,plan.protected_bytes)
            nextPendingBytes=max(0,plan.pending_bytes)
            receivedPlan=true
        } catch {}

        // The billed subscription remains independent from total capacity. Extra space
        // granted by Libérons is a bonus and must never appear as a more expensive plan.
        do {
            let subscriptions:[UserSubscription]=try await SupabaseService.client.from("user_subscriptions").select("plan_code,status").eq("user_id",value:userID).limit(1).execute().value
            if let sub=subscriptions.first,let code=sub.plan_code,!code.isEmpty {
                nextBilledPlanCode=code
                if let status=sub.status{nextSubscriptionStatus=status.lowercased()}
                let planRows:[PublicPlan]=try await SupabaseService.client.from("public_subscription_plans").select("code,quota_bytes,monthly_price_cents,currency").eq("code",value:code).limit(1).execute().value
                if let paid=planRows.first {
                    nextBilledPlanQuotaBytes=max(0,paid.quota_bytes)
                    nextBilledPlanPriceCents=max(0,paid.monthly_price_cents)
                    nextBilledPlanCurrency=paid.currency
                }
            }
        } catch {
            nextBilledPlanCode=billedPlanCode
            nextBilledPlanQuotaBytes=billedPlanQuotaBytes
            nextBilledPlanPriceCents=billedPlanPriceCents
            nextBilledPlanCurrency=billedPlanCurrency
        }

        // Asset rows are needed for the exact protected item count and most recent date.
        // This is intentionally event/manual-refresh driven now, never timer-polled.
        do {
            let pageSize=1000;var offset=0;var allAssets:[Asset]=[]
            while true {
                let response=try await SupabaseService.client.from("media_assets").select("protected_at,size_bytes").eq("user_id",value:userID).eq("status",value:"protected").order("protected_at",ascending:false).range(from:offset,to:offset+pageSize-1).execute()
                let page=try decoder.decode([Asset].self,from:response.data)
                allAssets.append(contentsOf:page)
                if page.count<pageSize{break}
                offset+=pageSize
            }
            nextProtectedCount=allAssets.count
            nextLastProtectedAt=allAssets.first?.protected_at
            // Keep account-storage-plan as the authoritative byte total when available.
            // Fall back to the paginated asset sum only if the server snapshot failed.
            if !receivedPlan { nextProtectedBytes=allAssets.reduce(Int64(0)){$0+max(0,$1.size_bytes ?? 0)} }
        } catch {}

        objectWillChange.send()
        quotaBytes=nextQuotaBytes
        accountRole=nextAccountRole
        subscriptionStatus=nextSubscriptionStatus
        gracePeriodEnd=nextGracePeriodEnd
        lastPaymentFailedAt=nextLastPaymentFailedAt
        billedPlanCode=nextBilledPlanCode
        billedPlanQuotaBytes=nextBilledPlanQuotaBytes
        billedPlanPriceCents=nextBilledPlanPriceCents
        billedPlanCurrency=nextBilledPlanCurrency
        protectedCount=nextProtectedCount
        lastProtectedAt=nextLastProtectedAt
        protectedBytes=nextProtectedBytes
        pendingBytes=nextPendingBytes
        planLoadFailed = !receivedPlan
    }
}
