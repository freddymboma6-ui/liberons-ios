import Foundation
import UIKit
import UserNotifications
import Supabase

@MainActor
final class PushNotificationManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()
    private override init() { super.init() }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            print("Push authorization failed: \(error)")
        }
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await save(token: token) }
    }

    func didFailToRegister(error: Error) {
        print("APNs registration failed: \(error)")
    }

    private func save(token: String) async {
        do {
            let session = try await SupabaseService.client.auth.session
            let installationID = installationIdentifier()
            #if DEBUG
            let environment = "sandbox"
            #else
            let environment = "production"
            #endif
            struct DeviceToken: Encodable {
                let user_id: UUID
                let installation_id: UUID
                let token: String
                let platform: String
                let environment: String
                let app_version: String?
                let locale: String
                let enabled: Bool
                let last_seen_at: String
            }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let row = DeviceToken(user_id: session.user.id, installation_id: installationID, token: token, platform: "ios", environment: environment, app_version: version, locale: Locale.current.identifier, enabled: true, last_seen_at: ISO8601DateFormatter().string(from: Date()))
            _ = try await SupabaseService.client.from("push_tokens").upsert(row, onConflict: "user_id,installation_id").execute()
        } catch {
            print("Push token save failed: \(error)")
        }
    }

    private func installationIdentifier() -> UUID {
        let key = "liberons.installation-id"
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) { return id }
        let id = UUID(); UserDefaults.standard.set(id.uuidString, forKey: key); return id
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run {
            NotificationCenter.default.post(name: .liberonsPushOpened, object: nil, userInfo: info)
        }
    }
}

extension Notification.Name {
    static let liberonsPushOpened = Notification.Name("liberons.push.opened")
}

final class LiberonsAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Task { @MainActor in PushNotificationManager.shared.configure() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushNotificationManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushNotificationManager.shared.didFailToRegister(error: error) }
    }
}
