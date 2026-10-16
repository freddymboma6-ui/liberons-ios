import SwiftUI
import UIKit

@main
struct LiberonsApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LocalStorageGuard.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    LocalStorageGuard.applicationDidReceiveMemoryWarning()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                LocalStorageGuard.applicationDidEnterBackground()
            }
        }
    }
}
