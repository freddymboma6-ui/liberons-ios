import SwiftUI
import UIKit
import Supabase
import Auth

extension Notification.Name {
    static let liberonsPullToRefresh = Notification.Name("liberons.pullToRefresh")
}

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
                .refreshable {
                    // Native iOS pull-to-refresh inherited by the app's scroll views.
                    // Individual screens that already provide a more specific refresh
                    // action (such as the protected Library) keep their own behavior.
                    NotificationCenter.default.post(name: .liberonsPullToRefresh, object: nil)
                    NotificationCenter.default.post(name: .liberonsCloudDidChange, object: nil)
                    // Keep the native spinner visible long enough to communicate the
                    // refresh without blocking interaction or starting heavy work here.
                    try? await Task.sleep(for: .milliseconds(350))
                }
                .task {
                    if (try? await SupabaseService.client.auth.session) != nil {
                        await PushNotificationManager.shared.requestAuthorizationAndRegister()
                        PresenceService.shared.start()
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
                PresenceService.shared.stop()
                LocalStorageGuard.applicationDidEnterBackground()
                ImmediateBackgroundExecution.shared.begin()
                BackgroundBackupScheduler.shared.schedule()
            } else if phase == .active {
                ImmediateBackgroundExecution.shared.end()
                Task {
                    if (try? await SupabaseService.client.auth.session) != nil {
                        await PushNotificationManager.shared.requestAuthorizationAndRegister()
                        PresenceService.shared.start()
                    } else {
                        PresenceService.shared.stop()
                    }
                }
            }
        }
    }
}
