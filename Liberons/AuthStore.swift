import Foundation
import Combine
import Supabase
import Auth

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = true
    @Published private(set) var freeTierEligible: Bool?
    @Published private(set) var appAttestVerified: Bool?
    @Published private(set) var isRestricted = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    var isAuthenticated: Bool { session != nil && !isRestricted }

    init() { Task { await restoreSession() } }

    func restoreSession() async {
        defer { isLoading = false }
        session = try? await SupabaseService.client.auth.session
        if session != nil {
            await refreshRestrictionState()
            if !isRestricted { await validateDeviceAndFreeTier() }
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil; infoMessage = nil
        do {
            session = try await SupabaseService.client.auth.signIn(email: email, password: password)
            await refreshRestrictionState()
            if isRestricted { errorMessage = "account_restricted"; return }
            await validateDeviceAndFreeTier()
        } catch { errorMessage = friendlyAuthError(error) }
    }

    func signUp(email: String, password: String) async -> Bool {
        errorMessage = nil; infoMessage = nil
        do {
            let response = try await SupabaseService.client.auth.signUp(email: email, password: password, redirectTo: URL(string: "https://liberons.com/auth/callback"))
            if let newSession = response.session {
                session = newSession
                await refreshRestrictionState()
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
            let rows: [RestrictionRow] = try await SupabaseService.client.from("user_subscriptions").select("restricted_at").eq("user_id", value: userID.uuidString).limit(1).execute().value
            isRestricted = rows.first?.restricted_at != nil
            if isRestricted { errorMessage = "account_restricted" }
        } catch { }
    }

    func sendPasswordReset(email: String) async -> Bool {
        errorMessage = nil; infoMessage = nil
        do { try await SupabaseService.client.auth.resetPasswordForEmail(email, redirectTo: URL(string: "liberons://auth/reset-password")); infoMessage = "password_reset_sent"; return true }
        catch { errorMessage = friendlyAuthError(error); return false }
    }

    func handleAuthURL(_ url: URL) async -> Bool {
        errorMessage = nil
        do { session = try await SupabaseService.client.auth.session(from: url); await refreshRestrictionState(); return !isRestricted }
        catch { errorMessage = friendlyAuthError(error); return false }
    }

    func updatePassword(_ password: String) async -> Bool {
        errorMessage = nil; infoMessage = nil
        do { try await SupabaseService.client.auth.update(user: UserAttributes(password: password)); infoMessage = "password_updated"; return true }
        catch { errorMessage = friendlyAuthError(error); return false }
    }

    func signOut() async {
        do { try await SupabaseService.client.auth.signOut(); session = nil; isRestricted = false; freeTierEligible = nil; appAttestVerified = nil; infoMessage = nil }
        catch { errorMessage = friendlyAuthError(error) }
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
