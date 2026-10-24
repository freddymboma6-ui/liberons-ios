import Foundation
import Combine
import UIKit
import Supabase
import Auth
import Realtime

extension Notification.Name {
    static let liberonsAuthSessionConfirmed = Notification.Name("liberons.authSessionConfirmed")
}

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = true
    @Published private(set) var freeTierEligible: Bool?
    @Published private(set) var appAttestVerified: Bool?
    @Published private(set) var isRestricted = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private var restrictionRealtimeTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    private var confirmationObserver: NSObjectProtocol?

    var isAuthenticated: Bool { session != nil && !isRestricted }

    init() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session != nil else { return }
                await self.refreshRestrictionState()
            }
        }
        confirmationObserver = NotificationCenter.default.addObserver(
            forName: .liberonsAuthSessionConfirmed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.restoreConfirmedSession()
            }
        }
        Task { await restoreSession() }
    }

    deinit {
        restrictionRealtimeTask?.cancel()
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        if let confirmationObserver { NotificationCenter.default.removeObserver(confirmationObserver) }
    }

    func restoreSession() async {
        isLoading = true
        defer { isLoading = false }

        // Never turn a temporary Keychain/network/token-refresh hiccup into a logout.
        // Supabase normally restores immediately from local storage, but after an iOS
        // memory termination the first refresh can race with app/network startup.
        var restoredSession: Session?
        var lastError: Error?

        for attempt in 0..<3 {
            do {
                restoredSession = try await SupabaseService.client.auth.session
                lastError = nil
                break
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
                }
            }
        }

        if let restoredSession {
            session = restoredSession
            errorMessage = nil
            await refreshRestrictionState()
            startRestrictionRealtime()
            if !isRestricted { await validateDeviceAndFreeTier() }
            return
        }

        // If this AuthStore already had a valid in-memory session, preserve it.
        // Only a real explicit signOut() is allowed to clear it here.
        if session != nil {
            await refreshRestrictionState()
            startRestrictionRealtime()
            return
        }

        // A failed restore is not proof that the user signed out. Keep the error
        // non-destructive so a subsequent foreground/relaunch can restore normally.
        if let lastError {
            let friendly = friendlyAuthError(lastError)
            if friendly == "auth_network_error" {
                errorMessage = friendly
            }
        }
    }

    private func restoreConfirmedSession() async {
        errorMessage = nil
        guard let confirmedSession = try? await SupabaseService.client.auth.session else { return }
        session = confirmedSession
        isLoading = false
        await refreshRestrictionState()
        startRestrictionRealtime()
        if isRestricted {
            errorMessage = "account_restricted"
            return
        }
        await validateDeviceAndFreeTier()
        infoMessage = "email_confirmed"
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil; infoMessage = nil
        do {
            session = try await SupabaseService.client.auth.signIn(email: email, password: password)
            await refreshRestrictionState()
            startRestrictionRealtime()
            if isRestricted { errorMessage = "account_restricted"; return }
            await validateDeviceAndFreeTier()
        } catch { errorMessage = friendlyAuthError(error) }
    }

    func signUp(email: String, password: String) async -> Bool {
        errorMessage = nil; infoMessage = nil
        do {
            let response = try await SupabaseService.client.auth.signUp(
                email: email,
                password: password,
                redirectTo: URL(string: "liberons://auth/confirm")
            )
            if let newSession = response.session {
                session = newSession
                await refreshRestrictionState()
                startRestrictionRealtime()
                if isRestricted { errorMessage = "account_restricted"; return false }
                await validateDeviceAndFreeTier()
                return true
            }
            infoMessage = "confirmation_required"
            return true
        } catch { errorMessage = friendlyAuthError(error); return false }
    }

    func refreshRestrictionState() async {
        guard let userID = session?.user.id else { isRestricted = false; return }
        struct RestrictionRow: Decodable { let restricted_at: String? }
        do {
            let rows: [RestrictionRow] = try await SupabaseService.client
                .from("user_subscriptions")
                .select("restricted_at")
                .eq("user_id", value: userID.uuidString)
                .limit(1)
                .execute().value
            let restricted = rows.first?.restricted_at != nil
            if restricted != isRestricted { isRestricted = restricted }
            if restricted { errorMessage = "account_restricted" }
            else if errorMessage == "account_restricted" { errorMessage = nil }
        } catch { }
    }

    private func startRestrictionRealtime() {
        restrictionRealtimeTask?.cancel()
        guard session != nil else { return }
        restrictionRealtimeTask = Task { [weak self] in
            guard let self else { return }
            let channel = SupabaseService.client.channel("liberons-account-access-\(UUID().uuidString)")
            let changes = channel.postgresChange(UpdateAction.self, schema: "public", table: "user_subscriptions")
            await channel.subscribe()
            for await _ in changes {
                if Task.isCancelled { break }
                await self.refreshRestrictionState()
            }
            await SupabaseService.client.removeChannel(channel)
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        errorMessage = nil; infoMessage = nil
        do { try await SupabaseService.client.auth.resetPasswordForEmail(email, redirectTo: URL(string: "liberons://auth/reset-password")); infoMessage = "password_reset_sent"; return true }
        catch { errorMessage = friendlyAuthError(error); return false }
    }

    func handleAuthURL(_ url: URL) async -> Bool {
        errorMessage = nil
        do {
            session = try await SupabaseService.client.auth.session(from: url)
            await refreshRestrictionState()
            startRestrictionRealtime()
            if isRestricted { errorMessage = "account_restricted"; return false }
            await validateDeviceAndFreeTier()
            infoMessage = "email_confirmed"
            return true
        } catch { errorMessage = friendlyAuthError(error); return false }
    }

    func updatePassword(_ password: String) async -> Bool {
        errorMessage = nil; infoMessage = nil
        do { try await SupabaseService.client.auth.update(user: UserAttributes(password: password)); infoMessage = "password_updated"; return true }
        catch { errorMessage = friendlyAuthError(error); return false }
    }

    func signOut() async {
        restrictionRealtimeTask?.cancel(); restrictionRealtimeTask = nil
        do {
            try await SupabaseService.client.auth.signOut()
            session = nil; isRestricted = false; freeTierEligible = nil; appAttestVerified = nil; infoMessage = nil
        } catch { errorMessage = friendlyAuthError(error) }
    }

    private func friendlyAuthError(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("invalid login credentials") || raw.contains("invalid credentials") { return "auth_invalid_credentials" }
        if raw.contains("email not confirmed") { return "auth_email_not_confirmed" }
        if raw.contains("user already registered") || raw.contains("already been registered") { return "auth_user_already_registered" }
        if raw.contains("password") && (raw.contains("least") || raw.contains("short") || raw.contains("characters")) { return "auth_password_too_short" }
        if raw.contains("email") && raw.contains("invalid") { return "auth_invalid_email" }
        if raw.contains("network") || raw.contains("internet") || raw.contains("offline") || raw.contains("connection") { return "auth_network_error" }
        if raw.contains("rate limit") || raw.contains("too many") { return "auth_too_many_requests" }
        return "auth_generic_error"
    }

    private func validateDeviceAndFreeTier() async {
        do { appAttestVerified = try await FreeTierProtection.registerAppAttestKeyIfSupported() } catch { appAttestVerified = nil }
        do { freeTierEligible = try await FreeTierProtection.validateFreeTier() } catch { freeTierEligible = nil }
    }
}
