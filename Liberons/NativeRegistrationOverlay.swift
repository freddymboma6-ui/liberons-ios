import SwiftUI
import Supabase

struct NativeRegistrationOverlay: ViewModifier {
    @State private var hasSession = true
    @State private var showingRegistration = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !hasSession {
                    HStack(spacing: 5) {
                        Text("Nouveau sur Libérons ?")
                            .foregroundStyle(.secondary)
                        Button("Créer un compte") { showingRegistration = true }
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Crée un compte Libérons gratuit directement dans l’application")
                }
            }
            .task { await refreshSessionState() }
            .sheet(isPresented: $showingRegistration, onDismiss: { Task { await refreshSessionState() } }) {
                NativeRegistrationView()
            }
    }

    @MainActor
    private func refreshSessionState() async {
        hasSession = (try? await SupabaseService.client.auth.session) != nil
    }
}

private struct NativeRegistrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Créer votre compte").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Commencez gratuitement avec 2 Go de stockage Libérons. Aucun achat n’est requis.").foregroundStyle(.secondary)
                    TextField("E-mail", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textContentType(.emailAddress).padding().background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    SecureField("Mot de passe", text: $password).textContentType(.newPassword).padding().background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    SecureField("Confirmer le mot de passe", text: $confirmation).textContentType(.newPassword).padding().background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    Text("8 caractères minimum.").font(.caption).foregroundStyle(.secondary)
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                    if let successMessage { Text(successMessage).font(.footnote).foregroundStyle(.green) }
                    Button { createAccount() } label: {
                        HStack { Spacer(); if isCreating { ProgressView().tint(.white) } else { Text("Créer mon compte gratuit").fontWeight(.semibold) }; Spacer() }.frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreating || !formIsValid)
                    Text("La création du compte n’effectue aucun achat et n’active aucun abonnement payant.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(LiberonsTheme.canvas.ignoresSafeArea())
            .navigationTitle("Libérons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
    }

    private var formIsValid: Bool { email.contains("@") && password.count >= 8 && password == confirmation }

    private func createAccount() {
        guard formIsValid else { return }
        isCreating = true; errorMessage = nil; successMessage = nil
        Task {
            do {
                let response = try await SupabaseService.client.auth.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                await MainActor.run {
                    isCreating = false
                    successMessage = response.session == nil ? "Compte créé. Consultez votre e-mail pour le confirmer, puis connectez-vous dans Libérons." : "Votre compte gratuit Libérons est prêt."
                }
                if response.session != nil { try? await Task.sleep(for: .milliseconds(700)); await MainActor.run { dismiss() } }
            } catch {
                await MainActor.run { isCreating = false; errorMessage = error.localizedDescription }
            }
        }
    }
}

extension View {
    func nativeLibéronsRegistration() -> some View { modifier(NativeRegistrationOverlay()) }
}
