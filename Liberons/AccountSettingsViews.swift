import SwiftUI
import Photos
import UserNotifications
import UIKit

private enum LiberonsWebDestination {
    case home, privacy, terms, refunds, support

    func url(for language: LanguageStore.Language) -> URL? {
        let english = language == .english
        let path: String
        switch self {
        case .home: path = english ? "/en" : "/"
        case .privacy: path = english ? "/en/privacy" : "/privacy"
        case .terms: path = english ? "/en/terms" : "/terms"
        case .refunds: path = english ? "/en/refund-policy" : "/refund-policy"
        case .support: path = english ? "/en/support" : "/support"
        }
        return URL(string: "https://liberons.com\(path)")
    }
}

private struct LiberonsExternalRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(.blue).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LiberonsNotificationSettingsView: View {
    @ObservedObject var language: LanguageStore
    @AppStorage("notify.backupComplete") private var backupComplete = true
    @AppStorage("notify.readyToFree") private var readyToFree = true
    @AppStorage("notify.backupInterrupted") private var backupInterrupted = true
    @AppStorage("notify.storageWarnings") private var storageWarnings = true
    @AppStorage("notify.backupReminder") private var backupReminder = false
    @State private var authorization: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            Section {
                statusRow
                if authorization == .notDetermined { Button(language.text("Allow notifications", "Autoriser les notifications")) { requestPermission() } }
                else if authorization == .denied { Button(language.text("Open iPhone Settings", "Ouvrir les réglages de l’iPhone")) { openSettings() } }
            } footer: { Text(language.text("Choose the alerts you want to receive from Libérons. You can change them at any time.", "Choisissez les alertes que vous souhaitez recevoir de Libérons. Vous pourrez les modifier à tout moment.")) }

            Section(language.text("Your backups", "Vos sauvegardes")) {
                notificationToggle(language.text("Backup finished", "Sauvegarde terminée"), subtitle: language.text("Know when your selected memories are safely saved.", "Soyez averti lorsque les souvenirs sélectionnés sont bien sauvegardés."), icon: "checkmark.circle.fill", isOn: $backupComplete)
                notificationToggle(language.text("Space can be freed", "Vous pouvez libérer de l’espace"), subtitle: language.text("Get an alert when saved memories can be removed from your iPhone to recover space.", "Recevez une alerte lorsque des souvenirs sauvegardés peuvent être retirés de l’iPhone pour récupérer de l’espace."), icon: "iphone.and.arrow.forward", isOn: $readyToFree)
                notificationToggle(language.text("Backup problem", "Problème de sauvegarde"), subtitle: language.text("Be notified if a backup stops or needs your attention.", "Soyez averti si une sauvegarde s’arrête ou nécessite votre attention."), icon: "exclamationmark.triangle.fill", isOn: $backupInterrupted)
            }

            Section(language.text("Space & reminders", "Espace et rappels")) {
                notificationToggle(language.text("Storage almost full", "Espace Libérons presque plein"), subtitle: language.text("Get a warning before your Libérons storage reaches its limit.", "Recevez une alerte avant que votre espace Libérons n’atteigne sa limite."), icon: "externaldrive.badge.exclamationmark", isOn: $storageWarnings)
                notificationToggle(language.text("Remind me to back up", "Me rappeler de sauvegarder"), subtitle: language.text("Receive an occasional reminder when new memories have not been backed up for a while.", "Recevez un rappel occasionnel lorsque de nouveaux souvenirs n’ont pas été sauvegardés depuis un moment."), icon: "clock.badge", isOn: $backupReminder)
            }

            if authorization == .authorized || authorization == .provisional || authorization == .ephemeral {
                Section { Button(language.text("Notification settings on iPhone", "Réglages des notifications sur l’iPhone")) { openSettings() } }
            }
        }
        .navigationTitle(language.text("Notifications", "Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAuthorization() }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: authorization == .denied ? "bell.slash.fill" : "bell.badge.fill").foregroundStyle(authorization == .denied ? .red : .blue).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) { Text(language.text("Notifications on this iPhone", "Notifications sur cet iPhone")); Text(statusText).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }
    }

    private func notificationToggle(_ title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { HStack(alignment: .top, spacing: 12) { Image(systemName: icon).frame(width: 24).padding(.top, 2); VStack(alignment: .leading, spacing: 3) { Text(title); Text(subtitle).font(.caption).foregroundStyle(.secondary) } } }.disabled(authorization == .denied)
    }
    private var statusText: String { switch authorization { case .authorized, .provisional, .ephemeral: return language.text("On", "Activées"); case .denied: return language.text("Off in iPhone Settings", "Désactivées dans les réglages de l’iPhone"); case .notDetermined: return language.text("Not set up yet", "Pas encore configurées"); @unknown default: return "—" } }
    private func refreshAuthorization() async { authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    private func requestPermission() { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); await refreshAuthorization() } }
    private func openSettings() { guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }; UIApplication.shared.open(url) }
}

struct LiberonsPrivacySecurityView: View {
    @ObservedObject var language: LanguageStore
    @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "photo.stack.fill").foregroundStyle(.blue).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) { Text(language.text("Photos access", "Accès aux photos")); Text(photoAccessText).font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Image(systemName: photoStatus == .authorized ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(photoStatus == .authorized ? .green : .secondary.opacity(0.45))
                }.contentShape(Rectangle()).onTapGesture { openAppSettings() }
            } footer: { Text(language.text("Libérons uses Photos access only for the backup, protection and recovery features you choose.", "Libérons utilise l’accès à Photos uniquement pour les fonctions de sauvegarde, de protection et de récupération que vous choisissez.")) }

            Section(language.text("Protection principles", "Principes de protection")) {
                Label(language.text("A memory is marked protected only after the cloud copy is confirmed.", "Un souvenir est marqué comme protégé uniquement après confirmation de sa copie dans le cloud."), systemImage: "checkmark.shield.fill")
                Label(language.text("Nothing is removed from your iPhone automatically. You remain in control.", "Rien n’est retiré automatiquement de votre iPhone. Vous gardez le contrôle."), systemImage: "hand.raised.fill")
                Label(language.text("Libérons does not sell your photos or videos or use them for targeted advertising.", "Libérons ne vend pas vos photos ou vidéos et ne les utilise pas pour de la publicité ciblée."), systemImage: "eye.slash.fill")
            }

            Section(language.text("Official policies", "Politiques officielles")) {
                external(.privacy, icon: "hand.raised.square.fill", language.text("Privacy Policy", "Politique de confidentialité"))
                external(.terms, icon: "doc.text.fill", language.text("Terms of Use", "Conditions d’utilisation"))
                external(.refunds, icon: "arrow.uturn.backward.circle.fill", language.text("Refund Policy", "Politique de remboursement"))
            } footer: { Text(language.text("Official policies open on liberons.com in the same language selected in the app.", "Les politiques officielles s’ouvrent sur liberons.com dans la même langue que celle sélectionnée dans l’app.")) }

            Section(language.text("This iPhone", "Cet iPhone")) { Button(language.text("Open Libérons settings", "Ouvrir les réglages de Libérons")) { openAppSettings() } }
        }
        .navigationTitle(language.text("Privacy & security", "Confidentialité et sécurité"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    }

    @ViewBuilder private func external(_ destination: LiberonsWebDestination, icon: String, _ title: String) -> some View {
        LiberonsExternalRow(icon: icon, title: title, subtitle: "liberons.com") { open(destination) }
    }
    private var photoAccessText: String { switch photoStatus { case .authorized: return language.text("All photos allowed", "Toutes les photos autorisées"); case .limited: return language.text("Selected photos only", "Certaines photos seulement"); case .denied, .restricted: return language.text("Access is off", "Accès désactivé"); case .notDetermined: return language.text("Not set up yet", "Pas encore configuré"); @unknown default: return "—" } }
    private func open(_ destination: LiberonsWebDestination) { guard let url = destination.url(for: language.language) else { return }; UIApplication.shared.open(url) }
    private func openAppSettings() { guard let url = URL(string: UIApplication.openSettingsURLString) else { return }; UIApplication.shared.open(url) }
}

struct LiberonsHelpSupportView: View {
    @ObservedObject var language: LanguageStore

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(language.text("Libérons Support", "Assistance Libérons"), systemImage: "message.badge.fill").font(.headline).foregroundStyle(.blue)
                    Text(language.text("Get help with backups, storage, restores, your account or billing. Never send your password or full card number to support.", "Obtenez de l’aide pour les sauvegardes, le stockage, les restaurations, votre compte ou la facturation. Ne transmettez jamais votre mot de passe ni votre numéro complet de carte au support."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }

            Section(language.text("Contact", "Contact")) {
                LiberonsExternalRow(icon: "envelope.fill", title: "support@liberons.com", subtitle: language.text("Email Libérons Support", "Écrire à l’assistance Libérons")) { emailSupport() }
                LiberonsExternalRow(icon: "safari.fill", title: language.text("Support on liberons.com", "Assistance sur liberons.com"), subtitle: language.text("Open the official help page", "Ouvrir la page d’aide officielle")) { open(.support) }
            }

            Section(language.text("Backup & space", "Sauvegarde et espace")) {
                faq(language.text("What happens when I free space?", "Que se passe-t-il quand je libère de l’espace ?"), language.text("Only originals already confirmed as protected are eligible. When you confirm removal, the iPhone copy is removed while the protected Libérons copy remains available.", "Seuls les originaux dont la protection a été confirmée sont éligibles. Lorsque vous confirmez le retrait, la copie de l’iPhone est supprimée tandis que la copie protégée dans Libérons reste disponible."))
                faq(language.text("Can I back up without freeing space?", "Puis-je sauvegarder sans libérer d’espace ?"), language.text("Yes. Backup and local removal are separate actions.", "Oui. La sauvegarde et le retrait local sont deux actions distinctes."))
                faq(language.text("What if my Libérons storage is full?", "Que se passe-t-il si mon stockage Libérons est plein ?"), language.text("Existing protected memories remain in your Library. New backups pause until enough capacity is available.", "Les souvenirs déjà protégés restent dans votre Bibliothèque. Les nouvelles sauvegardes sont suspendues jusqu’à ce que suffisamment d’espace soit disponible."))
            }

            Section(language.text("Account & billing", "Compte et facturation")) {
                faq(language.text("Does deleting the app cancel my subscription?", "Supprimer l’app annule-t-il mon abonnement ?"), language.text("No. Uninstalling Libérons or signing out does not cancel a subscription. Manage your plan using the official account and billing controls.", "Non. Désinstaller Libérons ou vous déconnecter n’annule pas un abonnement. Gérez votre forfait avec les contrôles officiels du compte et de facturation."))
                faq(language.text("Where can I read the official policies?", "Où consulter les politiques officielles ?"), language.text("Privacy, Terms of Use and Refund Policy are available on liberons.com and from Privacy & security in the app.", "La confidentialité, les conditions d’utilisation et la politique de remboursement sont disponibles sur liberons.com et dans Confidentialité et sécurité dans l’app."))
            }
        }
        .navigationTitle(language.text("Help & support", "Aide et support"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func faq(_ question: String, _ answer: String) -> some View { DisclosureGroup(question) { Text(answer).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 6) } }
    private func open(_ destination: LiberonsWebDestination) { guard let url = destination.url(for: language.language) else { return }; UIApplication.shared.open(url) }
    private func emailSupport() { guard let url = URL(string: "mailto:support@liberons.com?subject=Lib%C3%A9rons%20Support") else { return }; UIApplication.shared.open(url) }
}

struct LiberonsAboutView: View {
    @ObservedObject var language: LanguageStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28).fill(Color.blue.gradient).frame(width: 92, height: 92)
                    Image(systemName: "icloud.and.arrow.up.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(spacing: 6) {
                    Text("Libérons").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(language.text("Keep your memories. Free your space.", "Gardez vos souvenirs. Libérez votre espace.")).font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                aboutCard {
                    Text(language.text("Cloud storage designed around your memories", "Un stockage cloud pensé autour de vos souvenirs")).font(.title3.bold())
                    Text(language.text("Libérons helps you protect photos and videos in Libérons Cloud, recover space on your iPhone when you choose, and keep protected memories available from your account.", "Libérons vous aide à protéger vos photos et vidéos dans Libérons Cloud, à récupérer de l’espace sur votre iPhone lorsque vous le décidez et à garder vos souvenirs protégés accessibles depuis votre compte."))
                    Divider()
                    aboutPoint("checkmark.icloud.fill", language.text("Verified protection", "Protection vérifiée"), language.text("A media item is treated as protected only after the cloud copy is confirmed.", "Un média est considéré comme protégé uniquement après confirmation de sa copie dans le cloud."))
                    aboutPoint("iphone", language.text("You stay in control", "Vous gardez le contrôle"), language.text("Cloud backup and removal from your iPhone are separate actions.", "La sauvegarde cloud et le retrait de votre iPhone sont deux actions distinctes."))
                    aboutPoint("arrow.down.to.line.compact", language.text("Restore when needed", "Récupérez quand nécessaire"), language.text("Protected memories can be accessed from your Libérons Library and restored according to your account status.", "Les souvenirs protégés restent accessibles dans votre Bibliothèque Libérons et peuvent être restaurés selon l’état de votre compte."))
                }

                aboutCard {
                    Text(language.text("Official information", "Informations officielles")).font(.headline)
                    external(.home, icon: "globe", language.text("Visit liberons.com", "Visiter liberons.com"))
                    Divider()
                    external(.privacy, icon: "hand.raised.square.fill", language.text("Privacy Policy", "Politique de confidentialité"))
                    Divider()
                    external(.terms, icon: "doc.text.fill", language.text("Terms of Use", "Conditions d’utilisation"))
                    Divider()
                    external(.refunds, icon: "arrow.uturn.backward.circle.fill", language.text("Refund Policy", "Politique de remboursement"))
                }

                aboutCard {
                    HStack { Text(language.text("App version", "Version de l’app")); Spacer(); Text(version).foregroundStyle(.secondary) }
                    Divider()
                    HStack { Text(language.text("Service operator", "Exploitant du service")); Spacer(); Text("Freddy Mboma").foregroundStyle(.secondary) }
                    Divider()
                    HStack { Text(language.text("Based in", "Établi au")); Spacer(); Text(language.text("Canada", "Canada")).foregroundStyle(.secondary) }
                }

                Text(language.text("Official legal information and policies are published on liberons.com.", "Les informations juridiques et politiques officielles sont publiées sur liberons.com."))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("© 2026 Libérons").font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
            }.padding(24)
        }
        .background(LiberonsTheme.canvas)
        .navigationTitle(language.text("About Libérons", "À propos de Libérons"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func aboutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 14) { content() }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous)) }
    @ViewBuilder private func aboutPoint(_ icon: String, _ title: String, _ detail: String) -> some View { HStack(alignment: .top, spacing: 12) { Image(systemName: icon).foregroundStyle(.blue).frame(width: 24).padding(.top, 2); VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.bold()); Text(detail).font(.subheadline).foregroundStyle(.secondary) } } }
    @ViewBuilder private func external(_ destination: LiberonsWebDestination, icon: String, _ title: String) -> some View { LiberonsExternalRow(icon: icon, title: title, subtitle: "liberons.com") { open(destination) } }
    private func open(_ destination: LiberonsWebDestination) { guard let url = destination.url(for: language.language) else { return }; UIApplication.shared.open(url) }
    private var version: String { let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"; let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"; return "\(version) (\(build))" }
}
