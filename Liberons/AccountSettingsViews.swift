import SwiftUI
import Photos
import UserNotifications
import UIKit

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
                if authorization == .notDetermined {
                    Button(language.text("Allow notifications", "Autoriser les notifications")) { requestPermission() }
                } else if authorization == .denied {
                    Button(language.text("Open iPhone Settings", "Ouvrir les réglages de l’iPhone")) { openSettings() }
                }
            } footer: {
                Text(language.text("Choose the alerts you want to receive from Libérons. You can change them at any time.", "Choisissez les alertes que vous souhaitez recevoir de Libérons. Vous pourrez les modifier à tout moment."))
            }

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
                Section {
                    Button(language.text("Notification settings on iPhone", "Réglages des notifications sur l’iPhone")) { openSettings() }
                } footer: {
                    Text(language.text("Sound, banners and Lock Screen alerts are managed by iPhone Settings.", "Le son, les bannières et l’affichage sur l’écran verrouillé sont gérés dans les réglages de l’iPhone."))
                }
            }
        }
        .navigationTitle(language.text("Notifications", "Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAuthorization() }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: authorization == .denied ? "bell.slash.fill" : "bell.badge.fill").foregroundStyle(authorization == .denied ? Color.red : Color.blue).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text("Notifications on this iPhone", "Notifications sur cet iPhone"))
                Text(statusText).font(.caption).foregroundStyle(Color.secondary)
            }
            Spacer()
        }
    }

    private func notificationToggle(_ title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).frame(width: 24).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(Color.primary)
                    Text(subtitle).font(.caption).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.disabled(authorization == .denied)
    }

    private var statusText: String {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return language.text("On", "Activées")
        case .denied: return language.text("Off in iPhone Settings", "Désactivées dans les réglages de l’iPhone")
        case .notDetermined: return language.text("Not set up yet", "Pas encore configurées")
        @unknown default: return "—"
        }
    }

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
                    Image(systemName: "photo.stack.fill").foregroundStyle(Color.blue).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) { Text(language.text("Photos access", "Accès aux photos")); Text(photoAccessText).font(.caption).foregroundStyle(Color.secondary) }
                    Spacer()
                    Image(systemName: photoStatus == .authorized ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(photoStatus == .authorized ? Color.green : Color.secondary.opacity(0.45))
                }.contentShape(Rectangle()).onTapGesture { openAppSettings() }
            } footer: { Text(language.text("Libérons needs access only to save the photos and videos you choose and, when you ask, help you recover space on this iPhone.", "Libérons utilise cet accès pour sauvegarder les photos et vidéos que vous choisissez et, lorsque vous le demandez, vous aider à récupérer de l’espace sur cet iPhone.")) }
            Section(language.text("Your memories", "Vos souvenirs")) {
                Label(language.text("A memory must be safely saved in Libérons before the app can offer to remove its copy from this iPhone.", "Un souvenir doit d’abord être sauvegardé en toute sécurité dans Libérons avant que l’app puisse proposer de retirer sa copie de cet iPhone."), systemImage: "checkmark.shield.fill")
                Label(language.text("Nothing is removed from your iPhone automatically. You always decide when to free space.", "Rien n’est retiré automatiquement de votre iPhone. C’est toujours vous qui décidez quand libérer de l’espace."), systemImage: "hand.raised.fill")
                Label(language.text("Memories kept in Libérons remain available in your Library and can be saved back to Photos.", "Les souvenirs conservés dans Libérons restent accessibles dans votre Bibliothèque et peuvent être enregistrés à nouveau dans Photos."), systemImage: "arrow.down.to.line.compact")
            }
            Section(language.text("Your account", "Votre compte")) {
                Label(language.text("Your sign-in information is kept securely on this device.", "Vos informations de connexion sont conservées de façon sécurisée sur cet appareil."), systemImage: "lock.fill")
                Button(language.text("Open Libérons settings on iPhone", "Ouvrir les réglages de Libérons sur l’iPhone")) { openAppSettings() }
            }
        }.navigationTitle(language.text("Privacy & security", "Confidentialité et sécurité")).navigationBarTitleDisplayMode(.inline).onAppear { photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    }

    private var photoAccessText: String {
        switch photoStatus {
        case .authorized: return language.text("All photos allowed", "Toutes les photos autorisées")
        case .limited: return language.text("Selected photos only", "Certaines photos seulement")
        case .denied, .restricted: return language.text("Access is off", "Accès désactivé")
        case .notDetermined: return language.text("Not set up yet", "Pas encore configuré")
        @unknown default: return "—"
        }
    }
    private func openAppSettings() { guard let url = URL(string: UIApplication.openSettingsURLString) else { return }; UIApplication.shared.open(url) }
}

struct LiberonsHelpSupportView: View {
    @ObservedObject var language: LanguageStore
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(language.text("How Libérons keeps your memories safe", "Comment Libérons protège vos souvenirs"), systemImage: "shield.checkered").font(.headline)
                    Text(language.text("First, Libérons saves the memories you choose. Once they are safely stored, you can decide whether to keep the copies on your iPhone or remove them to recover space.", "Libérons sauvegarde d’abord les souvenirs que vous choisissez. Une fois qu’ils sont bien enregistrés, vous décidez de garder les copies sur votre iPhone ou de les retirer pour récupérer de l’espace.")).font(.subheadline).foregroundStyle(Color.secondary)
                }.padding(.vertical, 4)
            }
            Section(language.text("Backup & space", "Sauvegarde et espace")) {
                faq(language.text("What happens when I free space?", "Que se passe-t-il quand je libère de l’espace ?"), language.text("Libérons only offers memories that have already been safely saved. If you confirm, the copy on your iPhone is removed while the saved memory stays available in your Libérons Library.", "Libérons propose uniquement les souvenirs déjà sauvegardés en toute sécurité. Si vous confirmez, la copie présente sur votre iPhone est retirée, tandis que le souvenir sauvegardé reste accessible dans votre Bibliothèque Libérons."))
                faq(language.text("Can I back up without freeing space?", "Puis-je sauvegarder sans libérer d’espace ?"), language.text("Yes. Saving your memories and freeing space are two separate actions. You can keep both the Libérons copy and the copy on your iPhone for as long as you want.", "Oui. Sauvegarder vos souvenirs et libérer de l’espace sont deux actions différentes. Vous pouvez conserver à la fois la copie Libérons et celle de votre iPhone aussi longtemps que vous le souhaitez."))
                faq(language.text("What if a backup stops?", "Que faire si une sauvegarde s’arrête ?"), language.text("Keep Libérons open and check your internet connection. Your already saved memories remain safe. You can start the remaining backup again when your connection is stable.", "Gardez Libérons ouvert et vérifiez votre connexion Internet. Les souvenirs déjà sauvegardés restent en sécurité. Vous pourrez relancer ce qu’il reste à sauvegarder lorsque votre connexion sera stable."))
                faq(language.text("What happens when my Libérons space is full?", "Que se passe-t-il si mon espace Libérons est plein ?"), language.text("Your existing saved memories stay available. New backups pause until space becomes available or you change your Libérons plan.", "Vos souvenirs déjà sauvegardés restent accessibles. Les nouvelles sauvegardes s’arrêtent jusqu’à ce que de l’espace soit disponible ou que vous changiez de forfait Libérons."))
            }
            Section(language.text("Your memories", "Vos souvenirs")) {
                faq(language.text("Can I get a photo back on my iPhone?", "Puis-je récupérer une photo sur mon iPhone ?"), language.text("Yes. Open the memory in your Libérons Library and choose the option to save it back to Photos.", "Oui. Ouvrez le souvenir dans votre Bibliothèque Libérons et choisissez l’option permettant de l’enregistrer à nouveau dans Photos."))
                faq(language.text("What happens if I change iPhone?", "Que se passe-t-il si je change d’iPhone ?"), language.text("Sign in to the same Libérons account. Memories already saved to your account remain in your Libérons Library.", "Connectez-vous au même compte Libérons. Les souvenirs déjà sauvegardés sur votre compte restent dans votre Bibliothèque Libérons."))
                faq(language.text("Why does Libérons need access to Photos?", "Pourquoi Libérons a besoin d’accéder à Photos ?"), language.text("Libérons needs permission to read the photos and videos you choose to save. When you decide to free space, iPhone will still control the final removal from Photos.", "Libérons a besoin de votre autorisation pour lire les photos et vidéos que vous choisissez de sauvegarder. Lorsque vous décidez de libérer de l’espace, l’iPhone garde le contrôle de la suppression finale dans Photos."))
                faq(language.text("If I delete something from Libérons, can I undo it?", "Si je supprime un souvenir de Libérons, puis-je annuler ?"), language.text("A permanent deletion from Libérons removes the saved cloud copy. Libérons asks for confirmation before doing this. If the same memory still exists in Photos on your iPhone, that local copy is not removed by deleting the Libérons copy.", "Une suppression définitive dans Libérons efface la copie sauvegardée dans le cloud. Libérons vous demande confirmation avant de le faire. Si le même souvenir existe encore dans Photos sur votre iPhone, cette copie locale n’est pas retirée lorsque vous supprimez la copie Libérons."))
            }
            Section(language.text("Need more help?", "Besoin d’aide ?")) { Label(language.text("Support messaging is coming to Libérons. Until then, the answers above cover the main backup and storage actions.", "La messagerie avec l’assistance arrive dans Libérons. En attendant, les réponses ci-dessus couvrent les principales actions de sauvegarde et de stockage."), systemImage: "message.fill").foregroundStyle(Color.secondary) }
        }.navigationTitle(language.text("Help & support", "Aide et support")).navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func faq(_ question: String, _ answer: String) -> some View { DisclosureGroup(question) { Text(answer).font(.subheadline).foregroundStyle(Color.secondary).padding(.vertical, 6) } }
}

struct LiberonsAboutView: View {
    @ObservedObject var language: LanguageStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28).fill(Color.blue.gradient).frame(width: 92, height: 92)
                    Image(systemName: "icloud.and.arrow.up.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(Color.white)
                }
                VStack(spacing: 6) {
                    Text("Libérons").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(language.text("Keep your memories. Free your space.", "Gardez vos souvenirs. Libérez votre espace.")).font(.headline).foregroundStyle(Color.secondary).multilineTextAlignment(.center)
                }
                aboutCard {
                    Text(language.text("Your memories, without the storage stress", "Vos souvenirs, sans le stress du stockage")).font(.title3.bold())
                    Text(language.text("Libérons gives you a simple way to save the photos and videos that matter to you, then recover space on your iPhone without losing access to those memories.", "Libérons vous offre une façon simple de sauvegarder les photos et vidéos qui comptent pour vous, puis de récupérer de l’espace sur votre iPhone sans perdre l’accès à ces souvenirs."))
                    Divider()
                    aboutPoint("checkmark.icloud.fill", language.text("Save first", "Sauvegarder d’abord"), language.text("Your selected memories are saved to your Libérons account before you are offered the option to free space.", "Les souvenirs que vous choisissez sont sauvegardés sur votre compte Libérons avant que l’option de libérer de l’espace vous soit proposée."))
                    aboutPoint("iphone", language.text("You stay in control", "Vous gardez le contrôle"), language.text("Nothing is removed from your iPhone automatically. You decide what happens and when.", "Rien n’est retiré automatiquement de votre iPhone. Vous décidez de ce qui se passe et à quel moment."))
                    aboutPoint("photo.stack.fill", language.text("Your Library stays with you", "Votre Bibliothèque reste avec vous"), language.text("Saved memories remain available in Libérons and can be saved back to Photos when you need them.", "Les souvenirs sauvegardés restent accessibles dans Libérons et peuvent être enregistrés à nouveau dans Photos lorsque vous en avez besoin."))
                }
                aboutCard {
                    Text(language.text("Privacy & trust", "Confidentialité et confiance")).font(.headline)
                    Text(language.text("Libérons is built around a simple rule: saving a memory and removing its copy from your iPhone are separate actions. The app does not silently delete your photos or videos.", "Libérons repose sur une règle simple : sauvegarder un souvenir et retirer sa copie de votre iPhone sont deux actions différentes. L’app ne supprime pas vos photos ou vidéos en silence.")).foregroundStyle(Color.secondary)
                }
                aboutCard {
                    HStack { Text(language.text("App version", "Version de l’app")); Spacer(); Text(version).foregroundStyle(Color.secondary) }
                }
                Text("© 2026 Libérons").font(.caption).foregroundStyle(Color.secondary).padding(.bottom, 12)
            }.padding(24)
        }
        .background(LiberonsTheme.canvas)
        .navigationTitle(language.text("About Libérons", "À propos de Libérons"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func aboutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private func aboutPoint(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.blue).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.bold()); Text(detail).font(.subheadline).foregroundStyle(Color.secondary) }
        }
    }

    private var version: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
