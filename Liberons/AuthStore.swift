import Foundation
import Combine
import Supabase
import Auth

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    var isAuthenticated: Bool { session != nil }

    init() {
        Task { await restoreSession() }
    }

    func restoreSession() async {
        defer { isLoading = false }
        session = try? await SupabaseService.client.auth.session
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            session = try await SupabaseService.client.auth.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await SupabaseService.client.auth.signOut()
            session = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
