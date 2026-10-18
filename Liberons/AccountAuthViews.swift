import SwiftUI

struct SignUpView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var language: LanguageStore
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var creating = false

    var body: some View {
        Form {
            Section {
                TextField(language.text("Email", "E-mail"), text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textContentType(.emailAddress)
                SecureField(language.text("Password", "Mot de passe"), text: $password).textContentType(.newPassword)
                SecureField(language.text("Confirm password", "Confirmer le mot de passe"), text: $confirmation).textContentType(.newPassword)
            } footer: { Text(language.text("Create your Libérons account and start with 2 GB free.", "Créez votre compte Libérons et commencez avec 2 Go gratuits.")) }
            if password != confirmation && !confirmation.isEmpty { Section { Text(language.text("Passwords do not match.", "Les mots de passe ne correspondent pas.")).foregroundStyle(.red) } }
            if auth.infoMessage == "confirmation_required" { Section { Label(language.text("Check your email to confirm your account.", "Consultez votre e-mail pour confirmer votre compte."), systemImage: "envelope.badge.fill").foregroundStyle(.blue) } }
            if let error = auth.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            Section { Button { creating = true; Task { _ = await auth.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password); creating = false } } label: { HStack { Spacer(); if creating { ProgressView() } else { Text(language.text("Create account", "Créer un compte")).fontWeight(.semibold) }; Spacer() } }.disabled(creating || !email.contains("@") || password.count < 8 || password != confirmation) }
        }
        .scrollContentBackground(.hidden).background(LiberonsTheme.canvas.ignoresSafeArea()).navigationTitle(language.text("Create account", "Créer un compte")).navigationBarTitleDisplayMode(.inline)
    }
}

struct ForgotPasswordView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var language: LanguageStore
    @State private var email: String
    @State private var sending = false
    init(auth: AuthStore, language: LanguageStore, email: String = "") { self.auth = auth; self.language = language; _email = State(initialValue: email) }
    var body: some View {
        Form {
            Section { TextField(language.text("Email", "E-mail"), text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textContentType(.emailAddress) } footer: { Text(language.text("We’ll email you a secure link to create a new password.", "Nous vous enverrons un lien sécurisé par e-mail pour créer un nouveau mot de passe.")) }
            if auth.infoMessage == "password_reset_sent" { Section { Label(language.text("Reset email sent. Check your inbox.", "E-mail de réinitialisation envoyé. Consultez votre boîte de réception."), systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            if let error = auth.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            Section { Button { sending = true; Task { _ = await auth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines)); sending = false } } label: { HStack { Spacer(); if sending { ProgressView() } else { Text(language.text("Send reset link", "Envoyer le lien de réinitialisation")).fontWeight(.semibold) }; Spacer() } }.disabled(sending || !email.contains("@")) }
        }.scrollContentBackground(.hidden).background(LiberonsTheme.canvas.ignoresSafeArea()).navigationTitle(language.text("Forgot password", "Mot de passe oublié")).navigationBarTitleDisplayMode(.inline)
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
            Section { SecureField(language.text("New password", "Nouveau mot de passe"), text: $password).textContentType(.newPassword); SecureField(language.text("Confirm new password", "Confirmer le nouveau mot de passe"), text: $confirmation).textContentType(.newPassword) } footer: { Text(language.text("Use at least 8 characters.", "Utilisez au moins 8 caractères.")) }
            if password != confirmation && !confirmation.isEmpty { Section { Text(language.text("Passwords do not match.", "Les mots de passe ne correspondent pas.")).foregroundStyle(.red) } }
            if auth.infoMessage == "password_updated" { Section { Label(language.text("Password updated.", "Mot de passe modifié."), systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            if let error = auth.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            Section { Button { saving = true; Task { _ = await auth.updatePassword(password); saving = false } } label: { HStack { Spacer(); if saving { ProgressView() } else { Text(language.text("Update password", "Modifier le mot de passe")).fontWeight(.semibold) }; Spacer() } }.disabled(saving || password.count < 8 || password != confirmation) }
        }.scrollContentBackground(.hidden).background(LiberonsTheme.canvas.ignoresSafeArea()).navigationTitle(language.text("Password", "Mot de passe")).navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountSecurityView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var language: LanguageStore
    private var webPrefix: String { language.language == .english ? "/en" : "" }
    private func webURL(_ path: String) -> URL { URL(string: "https://liberons.com\(webPrefix)\(path)")! }
    var body: some View {
        List {
            Section { NavigationLink { ChangePasswordView(auth: auth, language: language) } label: { Label(language.text("Change password", "Modifier le mot de passe"), systemImage: "key.fill") } } header: { Text(language.text("Account security", "Sécurité du compte")) } footer: { Text(language.text("Your password protects access to your Libérons account and protected memories.", "Votre mot de passe protège l’accès à votre compte Libérons et à vos souvenirs protégés.")) }
            Section { NavigationLink { LiberonsPrivacySecurityView(language: language) } label: { Label(language.text("Privacy & data protection", "Confidentialité et protection des données"), systemImage: "lock.shield.fill") } } footer: { Text(language.text("Review how Libérons protects your memories and manages access on this iPhone.", "Consultez comment Libérons protège vos souvenirs et gère les accès sur cet iPhone.")) }
            Section(language.text("Official policies", "Politiques officielles")) {
                Link(destination: webURL("/privacy")) { Label(language.text("Privacy Policy", "Politique de confidentialité"), systemImage: "hand.raised.square.fill") }
                Link(destination: webURL("/terms")) { Label(language.text("Terms of Use", "Conditions d’utilisation"), systemImage: "doc.text.fill") }
                Link(destination: webURL("/refund-policy")) { Label(language.text("Refund Policy", "Politique de remboursement"), systemImage: "arrow.uturn.backward.circle.fill") }
            }
            Section { Link(destination: URL(string:"https://liberons.com")!) { Label(language.text("Open liberons.com", "Ouvrir liberons.com"), systemImage: "safari.fill") } } footer: { Text(language.text("Official policies open on liberons.com in the same language selected in the app.", "Les politiques officielles s’ouvrent sur liberons.com dans la même langue que celle sélectionnée dans l’app.")) }
        }
        .scrollContentBackground(.hidden).background(LiberonsTheme.canvas.ignoresSafeArea()).navigationTitle(language.text("Privacy & security", "Confidentialité et sécurité")).navigationBarTitleDisplayMode(.inline)
    }
}
