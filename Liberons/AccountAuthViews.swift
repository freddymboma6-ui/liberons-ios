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
    @State private var showDeleteConfirmation = false
    @State private var deletionBusy = false
    @State private var deletionDeadline: Date?
    @State private var deletionMessage: String?

    private struct DeletionResponse: Decodable {
        let purge_after: String?
        let purgeAfter: String?
        let scheduled_for: String?
        let error: String?
        let message: String?
    }

    private func fullRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
    private func webURL(_ destination: LiberonsWebDestination) -> URL { destination.url(for: language.language) ?? URL(string: "https://liberons.com")! }
    private func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
    private func requestDeletion() {
        guard !deletionBusy else { return }; deletionBusy = true; deletionMessage = nil
        Task {
            defer { Task { @MainActor in deletionBusy = false } }
            do {
                let data = try await SupabaseService.callFunction("request-account-deletion", json: Data("{}".utf8))
                let body = try? JSONDecoder().decode(DeletionResponse.self, from: data)
                let deadline = parseDate(body?.purge_after ?? body?.purgeAfter ?? body?.scheduled_for)
                await MainActor.run { deletionDeadline = deadline; showDeleteConfirmation = false; deletionMessage = language.text("Your account deletion is scheduled.", "La suppression de votre compte est programmée.") }
            } catch {
                let raw = error.localizedDescription
                await MainActor.run {
                    if raw.contains("subscription_cancellation_required") { deletionMessage = language.text("Cancel your subscription renewal first, then return here to delete your account.", "Résiliez d’abord le renouvellement de votre abonnement, puis revenez ici pour supprimer votre compte.") }
                    else { deletionMessage = language.text("Unable to schedule account deletion right now. Please try again.", "Impossible de programmer la suppression du compte pour le moment. Réessayez.") }
                }
            }
        }
    }
    private func cancelDeletion() {
        guard !deletionBusy else { return }; deletionBusy = true; deletionMessage = nil
        Task {
            defer { Task { @MainActor in deletionBusy = false } }
            do {
                _ = try await SupabaseService.callFunction("cancel-account-deletion", json: Data("{}".utf8))
                await MainActor.run { deletionDeadline = nil; deletionMessage = language.text("Account deletion cancelled. Your subscription will not restart automatically.", "Suppression du compte annulée. Votre abonnement ne sera pas réactivé automatiquement.") }
            } catch {
                await MainActor.run { deletionMessage = language.text("This deletion can no longer be cancelled, or the service is temporarily unavailable.", "Cette suppression ne peut plus être annulée, ou le service est temporairement indisponible.") }
            }
        }
    }

    var body: some View {
        List {
            Section { NavigationLink { ChangePasswordView(auth: auth, language: language) } label: { fullRow(language.text("Change password", "Modifier le mot de passe"), icon: "key.fill") } } header: { Text(language.text("Account security", "Sécurité du compte")) } footer: { Text(language.text("Your password protects access to your Libérons account and protected memories.", "Votre mot de passe protège l’accès à votre compte Libérons et à vos souvenirs protégés.")) }
            Section { NavigationLink { LiberonsPrivacySecurityView(language: language) } label: { fullRow(language.text("Privacy & data protection", "Confidentialité et protection des données"), icon: "lock.shield.fill") } } footer: { Text(language.text("Review how Libérons protects your memories and manages access on this iPhone.", "Consultez comment Libérons protège vos souvenirs et gère les accès sur cet iPhone.")) }
            Section(language.text("Official policies", "Politiques officielles")) {
                Link(destination: webURL(.privacy)) { fullRow(language.text("Privacy Policy", "Politique de confidentialité"), icon: "hand.raised.square.fill") }
                Link(destination: webURL(.terms)) { fullRow(language.text("Terms of Use", "Conditions d’utilisation"), icon: "doc.text.fill") }
                Link(destination: webURL(.refunds)) { fullRow(language.text("Refund Policy", "Politique de remboursement"), icon: "arrow.uturn.backward.circle.fill") }
            }
            Section {
                if let deletionDeadline {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(language.text("Account deletion scheduled", "Suppression du compte programmée"), systemImage: "clock.badge.exclamationmark").foregroundStyle(.red).font(.headline)
                        Text(language.text("Your Libérons Cloud content will be permanently deleted starting \(deletionDeadline.formatted(date: .long, time: .shortened)).", "Vos contenus Libérons Cloud seront supprimés définitivement à partir du \(deletionDeadline.formatted(date: .long, time: .shortened)).")).font(.footnote).foregroundStyle(.secondary)
                        Button(role: .destructive) { cancelDeletion() } label: { if deletionBusy { ProgressView() } else { Text(language.text("Cancel account deletion", "Annuler la suppression du compte")) } }.disabled(deletionBusy)
                    }.padding(.vertical, 5)
                } else if showDeleteConfirmation {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(language.text("Your account will be scheduled for deletion. After 3 days, all photos, videos and files stored in your Libérons Cloud will be permanently deleted and cannot be recovered.", "Votre compte sera programmé pour suppression. Après 3 jours, toutes vos photos, vidéos et tous vos fichiers stockés dans Libérons Cloud seront supprimés définitivement et ne pourront plus être récupérés.")).font(.footnote).foregroundStyle(.secondary)
                        Button(role: .destructive) { requestDeletion() } label: { if deletionBusy { ProgressView() } else { Text(language.text("Confirm account deletion", "Confirmer la suppression du compte")) } }.disabled(deletionBusy)
                        Button(language.text("Cancel", "Annuler")) { showDeleteConfirmation = false }.disabled(deletionBusy)
                    }.padding(.vertical, 5)
                } else {
                    Button(role: .destructive) { showDeleteConfirmation = true; deletionMessage = nil } label: { fullRow(language.text("Delete my account", "Supprimer mon compte"), icon: "trash.fill") }
                }
                if let deletionMessage { Text(deletionMessage).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text(language.text("Danger zone", "Zone sensible")) } footer: { Text(language.text("You have 3 days to cancel. Once permanent deletion begins, your Libérons Cloud content cannot be recovered.", "Vous disposez de 3 jours pour annuler. Une fois la suppression définitive commencée, vos contenus Libérons Cloud ne peuvent plus être récupérés.")) }
            Section { Link(destination: webURL(.home)) { fullRow(language.text("Open liberons.com", "Ouvrir liberons.com"), icon: "safari.fill") } } footer: { Text(language.text("Review Libérons legal and privacy information whenever you need it.", "Consultez les informations juridiques et de confidentialité de Libérons à tout moment.")) }
        }
        .scrollContentBackground(.hidden).background(LiberonsTheme.canvas.ignoresSafeArea()).navigationTitle(language.text("Privacy & security", "Confidentialité et sécurité")).navigationBarTitleDisplayMode(.inline)
    }
}
