import Foundation
import Combine
import Supabase
import Auth

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = true
    @Published private(set) var freeTierEligible: Bool?
    @Published var errorMessage: String?

    var isAuthenticated: Bool { session != nil }

    init() {
        Task { await restoreSession() }
    }

    func restoreSession() async {
        defer { isLoading = false }
        session = try? await SupabaseService.client.auth.session
        if session != nil { await validateFreeTier() }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            session = try await SupabaseService.client.auth.signIn(email: email, password: password)
            await validateFreeTier()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await SupabaseService.client.auth.signOut()
            session = nil
            freeTierEligible = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func validateFreeTier() async {
        do {
            freeTierEligible = try await FreeTierProtection.validateFreeTier()
        } catch {
            // A temporary network/server failure must never sign the user out or
            // accidentally grant another free allocation. The backend remains authoritative.
            freeTierEligible = nil
        }
    }
}
