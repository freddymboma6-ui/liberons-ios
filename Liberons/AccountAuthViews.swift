import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sending = false

    var body: some View {
        Form {
            Section {
                TextField(language.text("Email", "E-mail"), text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
            } footer: {
                Text(language.text("We’ll email you a secure link to create a new password.", "Nous vous enverrons un lien sécurisé par e-mail pour créer un nouveau mot de passe."))
            }

            if auth.infoMessage == "password_reset_sent" {
                Section { Label(language.text("Reset email sent. Check your inbox.", "E-mail de réinitialisation envoyé. Consultez votre boîte de réception."), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            if let error = auth.errorMessage { Section { Text(error).foregroundStyle(.red) } }

            Section {
                Button {
                    sending = true
                    Task { _ = await auth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines)); sending = false }
                } label: {
                    HStack { Spacer(); if sending { ProgressView() } else { Text(language.text("Send reset link", "Envoyer le lien de réinitialisation")).fontWeight(.semibold) }; Spacer() }
                }
                .disabled(sending || !email.contains("@"))
            }
        }
        .navigationTitle(language.text("Forgot password", "Mot de passe oublié"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ChangePasswordView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var language: LanguageStore
    @State private var password = ""
    @State private var confirmation = ""
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                SecureField(language.text("New password", "Nouveau mot de passe"), text: $password).textContentType(.newPassword)
                SecureField(language.text("Confirm new password", "Confirmer le nouveau mot de passe"), text: $confirmation).textContentType(.newPassword)
            } footer: {
                Text(language.text("Use at least 8 characters.", "Utilisez au moins 8 caractères."))
            }

            if password != confirmation && !confirmation.isEmpty { Section { Text(language.text("Passwords do not match.", "Les mots de passe ne correspondent pas.")).foregroundStyle(.red) } }
            if auth.infoMessage == "password_updated" { Section { Label(language.text("Password updated.", "Mot de passe modifié."), systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            if let error = auth.errorMessage { Section { Text(error).foregroundStyle(.red) } }

            Section {
                Button {
                    saving = true
                    Task { _ = await auth.updatePassword(password); saving = false }
                } label: {
                    HStack { Spacer(); if saving { ProgressView() } else { Text(language.text("Update password", "Modifier le mot de passe")).fontWeight(.semibold) }; Spacer() }
                }
                .disabled(saving || password.count < 8 || password != confirmation)
            }
        }
        .navigationTitle(language.text("Password", "Mot de passe"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
