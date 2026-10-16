import SwiftUI
import UIKit

@main
struct LiberonsApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LocalStorageGuard.configure()
        LiberonsTheme.configureGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .liberonsCanvas()
                .nativeLibéronsRegistration()
                .liberonsPasswordRecovery()
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
            if phase == .background { LocalStorageGuard.applicationDidEnterBackground() }
        }
    }
}
