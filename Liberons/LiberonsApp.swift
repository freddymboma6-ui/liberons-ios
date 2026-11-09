import SwiftUI
import UIKit
import Supabase
import Auth
import StoreKit

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
    @Environment(\.requestReview) private var requestReview
    @State private var registrationConfirmation: RegistrationConfirmationResult?
    @State private var availableUpdateURL: URL?
    @State private var showingUpdateAlert = false
    @AppStorage("liberons.review.launchCount") private var reviewLaunchCount = 0
    @AppStorage("liberons.review.lastPromptAt") private var lastReviewPromptAt = 0.0
    @AppStorage("liberons.update.lastCheckAt") private var lastUpdateCheckAt = 0.0

    @MainActor private func checkForAppStoreUpdate() async {
        let now = Date().timeIntervalSince1970
        guard now - lastUpdateCheckAt >= 12 * 3600,
              let bundleID = Bundle.main.bundleIdentifier,
              let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              var lookup = URLComponents(string: "https://itunes.apple.com/lookup") else { return }
        lastUpdateCheckAt = now
        lookup.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "ca")
        ]
        guard let url = lookup.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let app = (json["results"] as? [[String: Any]])?.first,
                  let latest = app["version"] as? String,
                  let storeURL = app["trackViewUrl"] as? String,
                  let destination = URL(string: storeURL),
                  latest.compare(currentVersion, options: .numeric) == .orderedDescending else { return }
            availableUpdateURL = destination
            showingUpdateAlert = true
        } catch {
            // Store lookup failures must never block Libérons.
        }
    }

    @MainActor private func considerNativeReviewPrompt() {
        reviewLaunchCount += 1
        let now = Date().timeIntervalSince1970
        guard reviewLaunchCount >= 5, now - lastReviewPromptAt >= 90 * 86400 else { return }
        lastReviewPromptAt = now
        requestReview()
    }


    init() {
        LocalStorageGuard.configure()
        LiberonsTheme.configureGlobalAppearance()
    }

    private var isFrench: Bool {
        if let saved = UserDefaults.standard.string(forKey: "liberons.language") { return saved == "fr" }
        return Locale.preferredLanguages.first?.hasPrefix("fr") == true
    }

    private var confirmationTitle: String { isFrench ? "Compte Libérons créé" : "Libérons account created" }

    private func confirmationMessage(for result: RegistrationConfirmationResult) -> String {
        switch result {
        case .freeTierGranted:
            return isFrench
                ? "Votre e-mail est confirmé. Votre compte Libérons est créé et vous bénéficiez de 2 Go de stockage gratuits."
                : "Your email is confirmed. Your Libérons account is created and includes 2 GB of free storage."
        case .freeTierAlreadyUsed:
            return isFrench
                ? "Votre e-mail est confirmé et votre compte Libérons est créé. Les 2 Go gratuits ont déjà été utilisés par un autre compte sur cet appareil, cette offre ne peut donc pas être accordée une seconde fois."
                : "Your email is confirmed and your Libérons account is created. The 2 GB free offer has already been used by another account on this device, so it cannot be granted a second time."
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
                    Button(isFrench ? "Continuer vers Libérons" : "Continue to Libérons") { registrationConfirmation = nil }
                } message: {
                    if let registrationConfirmation { Text(confirmationMessage(for: registrationConfirmation)) }
                }
                .alert(isFrench ? "Mise à jour disponible" : "Update available", isPresented: $showingUpdateAlert) {
                    Button(isFrench ? "Plus tard" : "Later", role: .cancel) {}
                    Button(isFrench ? "Mettre à jour" : "Update") {
                        if let availableUpdateURL { UIApplication.shared.open(availableUpdateURL) }
                    }
                } message: {
                    Text(isFrench ? "Une nouvelle version de Libérons est disponible sur l’App Store. Vous pouvez continuer à utiliser l’application." : "A new version of Libérons is available on the App Store. You can continue using the app.")
                }
                .onAppear {
                    considerNativeReviewPrompt()
                    Task { await checkForAppStoreUpdate() }
                }
                .refreshable {
                    NotificationCenter.default.post(name: .liberonsPullToRefresh, object: nil)
                    NotificationCenter.default.post(name: .liberonsCloudDidChange, object: nil)
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
                            await MainActor.run { NotificationCenter.default.post(name: .liberonsPasswordRecovery, object: nil) }
                        }
                    } else if isEmailConfirmation {
                        Task {
                            for _ in 0..<20 {
                                if (try? await SupabaseService.client.auth.session) != nil { break }
                                try? await Task.sleep(for: .milliseconds(150))
                            }
                            guard (try? await SupabaseService.client.auth.session) != nil else { return }

                            // Synchronize every AuthStore with the newly confirmed Supabase session.
                            // This closes the signup screen and routes the user into the authenticated app.
                            await MainActor.run {
                                NotificationCenter.default.post(name: .liberonsAuthSessionConfirmed, object: nil)
                            }

                            do {
                                let eligible = try await FreeTierProtection.validateFreeTier()
                                await MainActor.run {
                                    registrationConfirmation = eligible ? .freeTierGranted : .freeTierAlreadyUsed
                                    NotificationCenter.default.post(name: .liberonsCloudDidChange, object: nil)
                                }
                            } catch {
                                // The account is confirmed even if the entitlement check is temporarily unavailable.
                                // AuthStore remains authenticated and will retry the server check through its normal flow.
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
