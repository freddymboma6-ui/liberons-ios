import SwiftUI
import UIKit
import Supabase
import Auth

@main
struct LiberonsApp: App {
    @UIApplicationDelegateAdaptor(LiberonsAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LocalStorageGuard.configure()
        LiberonsTheme.configureGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            PublicAccessRootView()
                .liberonsCanvas()
                .liberonsPasswordRecovery()
                .task {
                    if (try? await SupabaseService.client.auth.session) != nil {
                        await PushNotificationManager.shared.requestAuthorizationAndRegister()
                    }
                }
                .onOpenURL { url in
                    let isRecovery = url.host == "auth" && url.path.contains("reset-password")
                    SupabaseService.client.auth.handle(url)
                    if isRecovery {
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            await MainActor.run {
                                NotificationCenter.default.post(name: .liberonsPasswordRecovery, object: nil)
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    LocalStorageGuard.applicationDidReceiveMemoryWarning()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                LocalStorageGuard.applicationDidEnterBackground()
            } else if phase == .active {
                Task {
                    if (try? await SupabaseService.client.auth.session) != nil {
                        await PushNotificationManager.shared.requestAuthorizationAndRegister()
                    }
                }
            }
        }
    }
}
