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

    var isAuthenticated: Bool { session != nil }

    init() {
        Task { await restoreSession() }
    }

    func restoreSession() async {
        defer { isLoading = false }
        session = try? await SupabaseService.client.auth.session
        if session != nil { await validateDeviceAndFreeTier() }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            session = try await SupabaseService.client.auth.signIn(email: email, password: password)
            await validateDeviceAndFreeTier()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await SupabaseService.client.auth.signOut()
            session = nil
            freeTierEligible = nil
            appAttestVerified = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// App Attest is an additional integrity signal, never a client-side entitlement decision.
    /// Unsupported devices continue through the server-side free-tier policy as Apple recommends.
    private func validateDeviceAndFreeTier() async {
        do {
            appAttestVerified = try await FreeTierProtection.registerAppAttestKeyIfSupported()
        } catch {
            // Network errors, unsupported/older devices, or an unavailable verifier must not
            // manufacture trust. Keep the state unknown and let the backend policy decide.
            appAttestVerified = nil
        }

        do {
            freeTierEligible = try await FreeTierProtection.validateFreeTier()
        } catch {
            // A temporary network/server failure must never sign the user out or
            // accidentally grant another free allocation. The backend remains authoritative.
            freeTierEligible = nil
        }
    }
}
