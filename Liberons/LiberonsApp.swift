import SwiftUI
import UIKit
import Supabase
import Auth

extension Notification.Name {
    static let liberonsPullToRefresh = Notification.Name("liberons.pullToRefresh")
}

private enum RegistrationConfirmationResult: String, Identifiable {
    case freeTierGranted
    case freeTierAlreadyUsed
    var id: String { rawValue }
}

@main
struct LiberonsApp: App {
    @UIApplicationDelegateAdaptor(LiberonsAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var registrationConfirmation: RegistrationConfirmationResult?

    init() {
        LocalStorageGuard.configure()
        LiberonsTheme.configureGlobalAppearance()
    }

    private var isFrench: Bool {
        if let saved = UserDefaults.standard.string(forKey: "liberons.language") {
            return saved == "fr"
        }
        return Locale.preferredLanguages.first?.hasPrefix("fr") == true
    }

    private var confirmationTitle: String {
        isFrench ? "Compte Libérons créé" : "Libérons account created"
    }

    private func confirmationMessage(for result: RegistrationConfirmationResult) -> String {
        switch result {
        case .freeTierGranted:
            return isFrench
                ? "Bienvenue ! Votre compte Libérons est confirmé et vous bénéficiez de 2 Go de stockage gratuits."
                : "Welcome! Your Libérons account is confirmed and includes 2 GB of free storage."
        case .freeTierAlreadyUsed:
            return isFrench
                ? "Votre compte Libérons est confirmé et actif. Les 2 Go gratuits ont déjà été attribués à un autre compte sur cet appareil, vous ne pouvez donc pas bénéficier une seconde fois de cette offre."
                : "Your Libérons account is confirmed and active. The 2 GB free offer has already been assigned to another account on this device, so this account cannot receive it again."
        }
    }

    var body: some Scene {
        WindowGroup {
            PublicAccessRootView()
                .liberonsCanvas()
                .liberonsPasswordRecovery()
                .alert(confirmationTitle, isPresented: Binding(
                    get: { registrationConfirmation != nil },
                    set: { if !$0 { registrationConfirmation = nil } }
                )) {
                    Button(isFrench ? "Continuer vers Libérons" : "Continue to Libérons") {
                        registrationConfirmation = nil
                    }
                } message: {
                    if let registrationConfirmation {
                        Text(confirmationMessage(for: registrationConfirmation))
                    }
                }
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
                    let isEmailConfirmation = url.host == "auth" && url.path.contains("confirm")
                    SupabaseService.client.auth.handle(url)

                    if isRecovery {
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            await MainActor.run {
                                NotificationCenter.default.post(name: .liberonsPasswordRecovery, object: nil)
                            }
                        }
                    } else if isEmailConfirmation {
                        Task {
                            // Supabase's URL handler first establishes the confirmed session.
                            // The server remains authoritative for the one-device free-tier rule.
                            for _ in 0..<12 {
                                if (try? await SupabaseService.client.auth.session) != nil { break }
                                try? await Task.sleep(for: .milliseconds(150))
                            }
                            guard (try? await SupabaseService.client.auth.session) != nil else { return }
                            do {
                                let eligible = try await FreeTierProtection.validateFreeTier()
                                await MainActor.run {
                                    registrationConfirmation = eligible ? .freeTierGranted : .freeTierAlreadyUsed
                                    NotificationCenter.default.post(name: .liberonsCloudDidChange, object: nil)
                                }
                            } catch {
                                // Do not guess eligibility if the authoritative server check fails.
                                // The account remains confirmed and the normal app flow can retry later.
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
