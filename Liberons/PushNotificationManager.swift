import Foundation
import UIKit
import UserNotifications
import Supabase

@MainActor
final class PushNotificationManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()
    private let cachedTokenKey = "liberons.apns-device-token"
    private var languageObserver: NSObjectProtocol?

    private override init() { super.init() }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        if languageObserver == nil {
            languageObserver = NotificationCenter.default.addObserver(forName: .liberonsLanguageChanged, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    await PushNotificationManager.shared.syncCachedTokenIfPossible()
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func requestAuthorizationAndRegister() async {
        do {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            var authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral

            if settings.authorizationStatus == .notDetermined {
                authorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            }

            guard authorized else {
                print("[Push] Notifications are not authorized (status: \(settings.authorizationStatus.rawValue))")
                return
            }

            await syncCachedTokenIfPossible()
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            print("[Push] Authorization/registration request failed: \(error.localizedDescription)")
        }
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: cachedTokenKey)
        print("[Push] APNs registration succeeded; syncing device token")
        Task { await save(token: token) }
    }

    func didFailToRegister(error: Error) {
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }

    func syncCachedTokenIfPossible() async {
        guard let token = UserDefaults.standard.string(forKey: cachedTokenKey), !token.isEmpty else { return }
        await save(token: token)
    }

    func sendBackupResult(completed: Int, failed: Int, total: Int) async {
        guard total > 0 else { return }
        let category = failed > 0 ? "backup_failed" : "backup_completed"
        let payload: [String: Any] = [
            "category": category,
            "data": [
                "completed": completed,
                "failed": failed,
                "total": total,
                "source": "ios_backup_batch"
            ]
        ]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            _ = try await SupabaseService.callFunction("send-push", json: body)
            print("[Push] Backup result notification requested: \(category) (\(completed)/\(total), failed: \(failed))")
        } catch {
            print("[Push] Backup result notification failed: \(String(describing: error))")
        }
    }

    private func selectedLanguage() -> String {
        if let value = UserDefaults.standard.string(forKey: "liberons.language"), ["fr", "en"].contains(value) { return value }
        return Locale.preferredLanguages.first?.hasPrefix("fr") == true ? "fr" : "en"
    }

    private func save(token: String) async {
        do {
            let session = try await SupabaseService.client.auth.session
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

            let row = DeviceToken(
                user_id: session.user.id,
                installation_id: installationIdentifier(),
                token: token,
                platform: "ios",
                environment: environment,
                app_version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                locale: selectedLanguage(),
                enabled: true,
                last_seen_at: ISO8601DateFormatter().string(from: Date())
            )

            try await SupabaseService.client
                .from("push_tokens")
                .upsert(row, onConflict: "user_id,installation_id")
                .execute()
            print("[Push] Device token saved to Supabase")
        } catch {
            print("[Push] Device token save failed: \(String(describing: error))")
        }
    }

    private func installationIdentifier() -> UUID {
        let key = "liberons.installation-id"
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
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
        BackgroundBackupScheduler.shared.register()
        LiberonsBackgroundUploader.shared.reconnect()
        Task { @MainActor in PushNotificationManager.shared.configure() }
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundBackupScheduler.shared.schedule()
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        LiberonsBackgroundUploader.shared.handleEvents(identifier: identifier, completionHandler: completionHandler)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushNotificationManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushNotificationManager.shared.didFailToRegister(error: error) }
    }
}