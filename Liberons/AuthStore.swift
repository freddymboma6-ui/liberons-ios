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
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    var isAuthenticated: Bool { session != nil }

    init() { Task { await restoreSession() } }

    func restoreSession() async {
        defer { isLoading = false }
        session = try? await SupabaseService.client.auth.session
        if session != nil { await validateDeviceAndFreeTier() }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil; infoMessage = nil
        do {
            session = try await SupabaseService.client.auth.signIn(email: email, password: password)
            await validateDeviceAndFreeTier()
        } catch { errorMessage = error.localizedDescription }
    }

    func signUp(email: String, password: String) async -> Bool {
        errorMessage = nil; infoMessage = nil
        do {
            let response = try await SupabaseService.client.auth.signUp(email: email, password: password, redirectTo: URL(string: "liberons://auth/confirm"))
            if let newSession = response.session {
                session = newSession
                await validateDeviceAndFreeTier()
                return true
            }
            infoMessage = "confirmation_required"
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func sendPasswordReset(email: String) async -> Bool {
        errorMessage = nil; infoMessage = nil
        do {
            try await SupabaseService.client.auth.resetPasswordForEmail(email, redirectTo: URL(string: "liberons://auth/reset-password"))
            infoMessage = "password_reset_sent"
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func handleAuthURL(_ url: URL) async -> Bool {
        errorMessage = nil
        do {
            session = try await SupabaseService.client.auth.session(from: url)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updatePassword(_ password: String) async -> Bool {
        errorMessage = nil; infoMessage = nil
        do {
            try await SupabaseService.client.auth.update(user: UserAttributes(password: password))
            infoMessage = "password_updated"
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func signOut() async {
        do {
            try await SupabaseService.client.auth.signOut()
            session = nil; freeTierEligible = nil; appAttestVerified = nil; infoMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func validateDeviceAndFreeTier() async {
        do { appAttestVerified = try await FreeTierProtection.registerAppAttestKeyIfSupported() } catch { appAttestVerified = nil }
        do { freeTierEligible = try await FreeTierProtection.validateFreeTier() } catch { freeTierEligible = nil }
    }
}
