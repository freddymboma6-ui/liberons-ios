import SwiftUI
import UserNotifications
import UIKit

private struct LibéronsStoreResult: Decodable {
    let resultCount: Int
    let results: [StoreApp]
    struct StoreApp: Decodable {
        let trackId: Int?
        let version: String?
        let trackViewUrl: URL?
    }
}


// Notification links are delivered in APNs userInfo.data.url by Libérons Admin.
@MainActor
final class LiberonsPushNavigation: ObservableObject {
    static let shared = LiberonsPushNavigation()
    @Published private(set) var destination: URL?
    private var opening = false

    func receive(_ userInfo: [AnyHashable: Any]) {
        let nested = userInfo["data"] as? [String: Any]
        let raw = (userInfo["url"] as? String)
            ?? (nested?["url"] as? String)
            ?? (userInfo["link"] as? String)
            ?? (nested?["link"] as? String)
        guard let raw,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else {
            print("Libérons push: no valid web destination in notification")
            return
        }
        destination = url
        openPendingIfPossible()
    }

    func openPendingIfPossible() {
        guard !opening, let url = destination else { return }
        // Open immediately when the notification is tapped, as Aurora does.
        // If iOS declines during launch, keep the destination for the next activation.
        opening = true
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                self.opening = false
                if success {
                    if self.destination == url { self.destination = nil }
                } else {
                    // Preserve the pending URL for the next activation attempt.
                    print("Libérons push: URL opening failed; retaining pending destination")
                }
            }
        }
    }
}

final class LiberonsNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if let payload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            Task { @MainActor in LiberonsPushNavigation.shared.receive(payload) }
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }
        let payload = response.notification.request.content.userInfo
        Task { @MainActor in
            LiberonsPushNavigation.shared.receive(payload)
        }
        completionHandler()
    }
}

@main
struct LiberonsApp: App {
    @UIApplicationDelegateAdaptor(LiberonsNotificationDelegate.self) private var notificationDelegate
    @StateObject private var pushNavigation = LiberonsPushNavigation.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOptionalUpdate = false
    @State private var storeURL: URL?
    @State private var storeVersion: String?
    @AppStorage("liberons.lastSuggestedStoreVersion") private var lastSuggestedVersion = ""

    @MainActor private func checkForUpdate() async {
        guard let bundleID = Bundle.main.bundleIdentifier,
              var components = URLComponents(string: "https://itunes.apple.com/lookup") else { return }
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "ca")
        ]
        guard let url = components.url else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(LibéronsStoreResult.self, from: data)
            guard let app = result.results.first,
                  let version = app.version,
                  let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  version.compare(installed, options: .numeric) == .orderedDescending,
                  version != lastSuggestedVersion,
                  let destination = app.trackViewUrl else { return }
            storeURL = destination
            storeVersion = version
            showOptionalUpdate = true
        } catch {
            // Unavailable App Store lookup must not block backups or browsing.
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    pushNavigation.openPendingIfPossible()
                    await checkForUpdate()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        pushNavigation.openPendingIfPossible()
                        Task { await checkForUpdate() }
                    }
                }
                .alert(
                    Locale.current.language.languageCode?.identifier == "fr"
                        ? "Nouvelle version Libérons" : "Libérons update available",
                    isPresented: $showOptionalUpdate
                ) {
                    Button(Locale.current.language.languageCode?.identifier == "fr" ? "Mettre à jour" : "Update") {
                        if let version = storeVersion { lastSuggestedVersion = version }
                        if let storeURL { UIApplication.shared.open(storeURL) }
                    }
                    Button(Locale.current.language.languageCode?.identifier == "fr" ? "Plus tard" : "Later", role: .cancel) {
                        if let version = storeVersion { lastSuggestedVersion = version }
                    }
                } message: {
                    Text(Locale.current.language.languageCode?.identifier == "fr"
                         ? "Une nouvelle version est disponible. Vous pouvez continuer à utiliser Libérons sans mettre à jour."
                         : "A new version is available. You can keep using Libérons without updating.")
                }
        }
    }
}
