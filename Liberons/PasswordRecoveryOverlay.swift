import SwiftUI
import Supabase

extension Notification.Name {
    static let liberonsPasswordRecovery = Notification.Name("liberonsPasswordRecovery")
}

struct PasswordRecoveryOverlay: ViewModifier {
    @State private var showingReset = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .liberonsPasswordRecovery)) { _ in
                showingReset = true
            }
            .sheet(isPresented: $showingReset) {
                InAppPasswordResetView()
            }
    }
}

private struct InAppPasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Nouveau mot de passe", text: $password).textContentType(.newPassword)
                    SecureField("Confirmer le nouveau mot de passe", text: $confirmation).textContentType(.newPassword)
                } footer: { Text("Utilisez au moins 8 caractères.") }

                if password != confirmation && !confirmation.isEmpty {
                    Section { Text("Les mots de passe ne correspondent pas.").foregroundStyle(.red) }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                if saved { Section { Label("Mot de passe modifié.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }

                Section {
                    Button {
                        saving = true; errorMessage = nil
                        Task {
                            do {
                                try await SupabaseService.client.auth.update(user: UserAttributes(password: password))
                                await MainActor.run { saving = false; saved = true }
                                try? await Task.sleep(for: .milliseconds(900))
                                await MainActor.run { dismiss() }
                            } catch {
                                await MainActor.run { saving = false; errorMessage = error.localizedDescription }
                            }
                        }
                    } label: {
                        HStack { Spacer(); if saving { ProgressView() } else { Text("Modifier le mot de passe").fontWeight(.semibold) }; Spacer() }
                    }
                    .disabled(saving || password.count < 8 || password != confirmation)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LiberonsTheme.canvas.ignoresSafeArea())
            .navigationTitle("Réinitialiser le mot de passe")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension View {
    func liberonsPasswordRecovery() -> some View { modifier(PasswordRecoveryOverlay()) }
}
