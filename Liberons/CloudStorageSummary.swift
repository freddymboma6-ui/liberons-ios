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

    private var observer:NSObjectProtocol?; private var refreshTimer:Timer?
    private struct Subscription: Decodable { let status:String?;let grace_period_end:Date?;let last_payment_failed_at:Date? }
    private struct ServerPlan: Decodable { let user_id:String;let quota_bytes:Int64;let protected_bytes:Int64;let pending_bytes:Int64;let role:String;let source:String;let subscription:Subscription? }
    private struct StorageQuota: Decodable { let quota_bytes:Int64 }
    private struct UserSubscription: Decodable { let plan_code:String?;let status:String? }
    private struct PublicPlan: Decodable { let code:String;let quota_bytes:Int64;let monthly_price_cents:Int;let currency:String }
    private struct Asset: Decodable { let protected_at:Date?;let size_bytes:Int64? }

    init(){observer=NotificationCenter.default.addObserver(forName:.liberonsCloudDidChange,object:nil,queue:.main){[weak self] _ in Task{@MainActor in await self?.refresh()}};refreshTimer=Timer.scheduledTimer(withTimeInterval:20,repeats:true){[weak self] _ in Task{@MainActor in await self?.refresh()}}}
    deinit{if let observer{NotificationCenter.default.removeObserver(observer)};refreshTimer?.invalidate()}

    func refresh() async {
        guard !isLoading else{return};isLoading=true;defer{isLoading=false}
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        guard let session=try? await SupabaseService.client.auth.session else{planLoadFailed=true;return}
        let userID=session.user.id.uuidString;var receivedPlan=false
        do{let plan:ServerPlan=try await SupabaseService.client.functions.invoke("account-storage-plan",options:FunctionInvokeOptions(headers:["Authorization":"Bearer \(session.accessToken)"]),decode:{data,_ in try decoder.decode(ServerPlan.self,from:data)});guard plan.user_id.lowercased()==userID.lowercased(),plan.source=="server" else{throw NSError(domain:"LiberonsPlan",code:1)};quotaBytes=max(0,plan.quota_bytes);accountRole=plan.role.lowercased();subscriptionStatus=plan.subscription?.status?.lowercased() ?? "free";gracePeriodEnd=plan.subscription?.grace_period_end;lastPaymentFailedAt=plan.subscription?.last_payment_failed_at;receivedPlan=true}catch{}
        do{let rows:[StorageQuota]=try await SupabaseService.client.from("storage_usage").select("quota_bytes").eq("user_id",value:userID).limit(1).execute().value;if let fresh=rows.first{quotaBytes=max(0,fresh.quota_bytes);receivedPlan=true}}catch{}

        // The subscription is deliberately loaded independently from quotaBytes.
        // Owner-granted capacity must never masquerade as a more expensive paid plan.
        billedPlanCode="free";billedPlanQuotaBytes=Self.freeQuotaBytes;billedPlanPriceCents=0;billedPlanCurrency="USD"
        do {
            let subscriptions:[UserSubscription]=try await SupabaseService.client.from("user_subscriptions").select("plan_code,status").eq("user_id",value:userID).limit(1).execute().value
            if let sub=subscriptions.first,let code=sub.plan_code,!code.isEmpty {
                billedPlanCode=code; if let status=sub.status{subscriptionStatus=status.lowercased()}
                let planRows:[PublicPlan]=try await SupabaseService.client.from("public_subscription_plans").select("code,quota_bytes,monthly_price_cents,currency").eq("code",value:code).limit(1).execute().value
                if let paid=planRows.first{billedPlanQuotaBytes=max(0,paid.quota_bytes);billedPlanPriceCents=max(0,paid.monthly_price_cents);billedPlanCurrency=paid.currency}
            }
        } catch {}
        planLoadFailed = !receivedPlan

        do{let pageSize=1000;var offset=0;var allAssets:[Asset]=[];while true{let response=try await SupabaseService.client.from("media_assets").select("protected_at,size_bytes").eq("user_id",value:userID).eq("status",value:"protected").order("protected_at",ascending:false).range(from:offset,to:offset+pageSize-1).execute();let page=try decoder.decode([Asset].self,from:response.data);allAssets.append(contentsOf:page);if page.count<pageSize{break};offset+=pageSize};protectedCount=allAssets.count;lastProtectedAt=allAssets.first?.protected_at;protectedBytes=allAssets.reduce(Int64(0)){$0+max(0,$1.size_bytes ?? 0)};pendingBytes=0}catch{}
    }
}
