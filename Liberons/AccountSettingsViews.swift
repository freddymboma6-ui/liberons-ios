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
                Section { Button(language.text("Notification settings on iPhone", "Réglages des notifications sur l’iPhone")) { openSettings() } } footer: { Text(language.text("Sound, banners and Lock Screen alerts are managed by iPhone Settings.", "Le son, les bannières et l’affichage sur l’écran verrouillé sont gérés dans les réglages de l’iPhone.")) }
            }
        }.navigationTitle(language.text("Notifications", "Notifications")).navigationBarTitleDisplayMode(.inline).task { await refreshAuthorization() }
    }
    private var statusRow: some View { HStack(spacing: 12) { Image(systemName: authorization == .denied ? "bell.slash.fill" : "bell.badge.fill").foregroundStyle(authorization == .denied ? Color.red : Color.blue).frame(width: 24); VStack(alignment: .leading, spacing: 2) { Text(language.text("Notifications on this iPhone", "Notifications sur cet iPhone")); Text(statusText).font(.caption).foregroundStyle(.secondary) }; Spacer() } }
    private func notificationToggle(_ title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View { Toggle(isOn: isOn) { HStack(alignment: .top, spacing: 12) { Image(systemName: icon).frame(width: 24).padding(.top, 2); VStack(alignment: .leading, spacing: 3) { Text(title); Text(subtitle).font(.caption).foregroundStyle(.secondary) } } }.disabled(authorization == .denied) }
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
            Section { HStack(spacing: 12) { Image(systemName: "photo.stack.fill").foregroundStyle(.blue).frame(width: 24); VStack(alignment: .leading, spacing: 2) { Text(language.text("Photos access", "Accès aux photos")); Text(photoAccessText).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: photoStatus == .authorized ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(photoStatus == .authorized ? Color.green : Color.secondary.opacity(0.45)) }.contentShape(Rectangle()).onTapGesture { openAppSettings() } } footer: { Text(language.text("Libérons uses Photos access only for the backup, protection and recovery features you choose.", "Libérons utilise l’accès à Photos uniquement pour les fonctions de sauvegarde, de protection et de récupération que vous choisissez.")) }
            Section(language.text("Protection principles", "Principes de protection")) {
                Label(language.text("A memory is marked protected only after the cloud copy is confirmed.", "Un souvenir est marqué comme protégé uniquement après confirmation de sa copie dans le cloud."), systemImage: "checkmark.shield.fill")
                Label(language.text("Nothing is removed from your iPhone automatically. You remain in control.", "Rien n’est retiré automatiquement de votre iPhone. Vous gardez le contrôle."), systemImage: "hand.raised.fill")
                Label(language.text("Libérons does not sell your photos or videos or use them for targeted advertising.", "Libérons ne vend pas vos photos ou vidéos et ne les utilise pas pour de la publicité ciblée."), systemImage: "eye.slash.fill")
            }
            Section {
                external(.privacy, icon: "hand.raised.square.fill", language.text("Privacy Policy", "Politique de confidentialité"))
                external(.terms, icon: "doc.text.fill", language.text("Terms of Use", "Conditions d’utilisation"))
                external(.refunds, icon: "arrow.uturn.backward.circle.fill", language.text("Refund Policy", "Politique de remboursement"))
            } header: { Text(language.text("Legal & privacy", "Cadre juridique et confidentialité")) }
            footer: { Text(language.text("Review the terms and privacy commitments that apply to your Libérons account.", "Consultez les conditions et engagements de confidentialité applicables à votre compte Libérons.")) }
            Section(language.text("This iPhone", "Cet iPhone")) { Button(language.text("Open Libérons settings", "Ouvrir les réglages de Libérons")) { openAppSettings() } }
        }.navigationTitle(language.text("Privacy & security", "Confidentialité et sécurité")).navigationBarTitleDisplayMode(.inline).onAppear { photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    }
    @ViewBuilder private func external(_ destination: LiberonsWebDestination, icon: String, _ title: String) -> some View { LiberonsExternalRow(icon: icon, title: title, subtitle: language.text("View document", "Consulter le document")) { open(destination) } }
    private var photoAccessText: String { switch photoStatus { case .authorized: return language.text("All photos allowed", "Toutes les photos autorisées"); case .limited: return language.text("Selected photos only", "Certaines photos seulement"); case .denied, .restricted: return language.text("Access is off", "Accès désactivé"); case .notDetermined: return language.text("Not set up yet", "Pas encore configuré"); @unknown default: return "—" } }
    private func open(_ destination: LiberonsWebDestination) { guard let url = destination.url(for: language.language) else { return }; UIApplication.shared.open(url) }
    private func openAppSettings() { guard let url = URL(string: UIApplication.openSettingsURLString) else { return }; UIApplication.shared.open(url) }
}

struct LiberonsHelpSupportView: View {
    @ObservedObject var language: LanguageStore
    @State private var searchText = ""
    @State private var selectedCategory = "all"

    private struct FAQItem: Identifiable {
        let id: String
        let category: String
        let questionEN: String
        let questionFR: String
        let answerEN: String
        let answerFR: String
        let keywords: String
    }

    private var categories: [(String, String, String)] { [
        ("all", "All", "Tout"), ("backup", "Backup", "Sauvegarde"), ("space", "Space", "Espace"),
        ("restore", "Restore", "Récupération"), ("account", "Account", "Compte"), ("billing", "Billing", "Facturation"),
        ("security", "Security", "Sécurité"), ("troubleshooting", "Problems", "Problèmes")
    ] }

    private var items: [FAQItem] { [
        item("protected", "backup", "When is a photo or video considered protected?", "Quand une photo ou vidéo est-elle considérée comme protégée ?", "Only after the original has been uploaded and Libérons has confirmed the cloud copy. A file is never marked protected simply because an upload started.", "Uniquement après l’envoi de l’original et la confirmation de sa copie dans le cloud par Libérons. Un fichier n’est jamais marqué protégé simplement parce qu’un envoi a commencé.", "protected cloud confirmation sauvegarde protégé upload original confirmation"),
        item("background", "backup", "Can a backup continue when I leave the app?", "La sauvegarde peut-elle continuer quand je quitte l’app ?", "Libérons uses iOS background capabilities when available. iOS can still pause background work depending on battery, network, system conditions or if the app is force-quit. Reopen Libérons to let the queue resume when needed.", "Libérons utilise les capacités d’arrière-plan d’iOS lorsqu’elles sont disponibles. iOS peut toutefois suspendre le travail selon la batterie, le réseau, l’état du système ou si l’app est forcée à quitter. Rouvrez Libérons pour permettre à la file de reprendre si nécessaire.", "background arrière plan fermer quitter pause upload batterie réseau"),
        item("wifi", "backup", "Do I need Wi-Fi to back up?", "Ai-je besoin du Wi-Fi pour sauvegarder ?", "Not necessarily. Availability depends on your backup preferences and network access. Large libraries are usually more comfortable to protect on a stable Wi-Fi connection.", "Pas nécessairement. Cela dépend de vos préférences de sauvegarde et de l’accès réseau. Pour une grande photothèque, une connexion Wi-Fi stable est généralement préférable.", "wifi wi-fi cellular mobile data données réseau internet"),
        item("icloud", "backup", "What if an original is only in iCloud Photos?", "Et si l’original est seulement dans Photos iCloud ?", "Libérons can ask Photos for the original when iOS makes it available. The item may take longer because the iPhone must first retrieve it from iCloud before Libérons can protect it.", "Libérons peut demander l’original à Photos lorsqu’iOS le rend disponible. L’opération peut prendre plus de temps car l’iPhone doit d’abord récupérer le fichier depuis iCloud avant que Libérons puisse le protéger.", "icloud apple photos original télécharger nuage cloud"),
        item("pause", "backup", "Can I pause or stop a backup?", "Puis-je mettre une sauvegarde en pause ou l’arrêter ?", "Yes. You can pause or stop the active queue. Items already confirmed as protected remain protected.", "Oui. Vous pouvez mettre en pause ou arrêter la file active. Les éléments déjà confirmés comme protégés restent protégés.", "pause stop arrêter reprendre resume queue file"),
        item("failed", "troubleshooting", "Why did a backup fail?", "Pourquoi une sauvegarde a-t-elle échoué ?", "Common causes include a lost connection, an original that Photos or iCloud could not provide, insufficient Libérons capacity, or a temporary cloud service error. Libérons retries transient failures and can stop a mass queue when the same error repeats, rather than failing thousands of items blindly.", "Les causes fréquentes sont une perte de connexion, un original indisponible dans Photos ou iCloud, un espace Libérons insuffisant ou une erreur temporaire du service cloud. Libérons réessaie les erreurs temporaires et peut arrêter une grande file si la même erreur se répète, plutôt que d’échouer des milliers d’éléments sans contrôle.", "failed échoué erreur upload réseau quota stockage backblaze retry réessayer"),
        item("duplicates", "backup", "Will Libérons upload the same memory again?", "Libérons va-t-il renvoyer le même souvenir ?", "Libérons is designed to identify protected media and avoid unnecessary duplicate protection work. A file should only count against your storage when it is actually stored for your account.", "Libérons est conçu pour reconnaître les médias protégés et éviter les sauvegardes en double inutiles. Un fichier ne doit compter dans votre stockage que lorsqu’il est réellement stocké pour votre compte.", "duplicate doublon twice deux fois stockage hash"),
        item("free-space", "space", "What happens when I free space?", "Que se passe-t-il quand je libère de l’espace ?", "Only originals already confirmed as protected are eligible. After you approve the iOS Photos deletion, the local copy is removed while the protected Libérons copy remains in your Library.", "Seuls les originaux dont la protection a été confirmée sont éligibles. Après votre confirmation de suppression dans Photos iOS, la copie locale est retirée tandis que la copie protégée reste dans votre Bibliothèque Libérons.", "free space libérer espace supprimer delete iphone local"),
        item("automatic-delete", "space", "Does Libérons delete photos automatically?", "Libérons supprime-t-il mes photos automatiquement ?", "No. Backup and local deletion are separate actions. Libérons requires your action before asking iOS Photos to remove protected originals from the device.", "Non. La sauvegarde et la suppression locale sont deux actions distinctes. Libérons nécessite votre action avant de demander à Photos iOS de retirer des originaux protégés de l’appareil.", "automatic automatiquement suppression delete contrôle permission"),
        item("recently-deleted", "space", "Why is space not fully recovered after deletion?", "Pourquoi l’espace n’est-il pas entièrement récupéré après la suppression ?", "Apple Photos normally moves deleted media to Recently Deleted. iOS does not allow Libérons to empty that album for you. To recover the space immediately, open Photos, go to Recently Deleted and permanently delete the items yourself.", "Photos d’Apple place normalement les médias supprimés dans Supprimés récemment. iOS n’autorise pas Libérons à vider cet album à votre place. Pour récupérer l’espace immédiatement, ouvrez Photos, allez dans Supprimés récemment et supprimez définitivement les éléments vous-même.", "recently deleted supprimés récemment espace corbeille photos apple vider"),
        item("backup-only", "space", "Can I back up without freeing space?", "Puis-je sauvegarder sans libérer d’espace ?", "Yes. Protecting media does not require you to remove the iPhone copy. You decide if and when you want to reclaim local space.", "Oui. Protéger vos médias ne vous oblige pas à retirer la copie de l’iPhone. Vous décidez si et quand vous souhaitez récupérer de l’espace local.", "backup only sauvegarder garder iphone sans supprimer"),
        item("full", "space", "What happens when my Libérons storage is full?", "Que se passe-t-il si mon stockage Libérons est plein ?", "Existing protected memories remain in your Library. New protection uploads pause until capacity becomes available or your plan provides more storage.", "Les souvenirs déjà protégés restent dans votre Bibliothèque. Les nouvelles sauvegardes sont suspendues jusqu’à ce que de l’espace soit disponible ou que votre forfait fournisse davantage de stockage.", "full plein quota capacity capacité forfait stockage"),
        item("restore", "restore", "Can I restore a protected memory to Photos?", "Puis-je restaurer un souvenir protégé dans Photos ?", "Yes. When your account permits original recovery, Libérons can retrieve the protected original and save it back to your photo library after the required Photos permission.", "Oui. Lorsque votre compte autorise la récupération des originaux, Libérons peut récupérer l’original protégé et le réenregistrer dans votre photothèque après l’autorisation Photos nécessaire.", "restore restauration récupérer recovery galerie photos original"),
        item("new-phone", "restore", "What happens if I change or lose my iPhone?", "Que se passe-t-il si je change ou perds mon iPhone ?", "Sign in to the same Libérons account on your new device. Protected cloud media belongs to your account, not to one physical iPhone. Security checks and permissions may be required on the new device.", "Connectez-vous au même compte Libérons sur le nouvel appareil. Les médias protégés dans le cloud sont liés à votre compte, pas à un seul iPhone physique. Des vérifications de sécurité et autorisations peuvent être demandées sur le nouvel appareil.", "new phone nouveau téléphone perdu cassé change appareil device restore"),
        item("restore-limit", "restore", "Why can original restores be temporarily limited?", "Pourquoi les restaurations d’originaux peuvent-elles être temporairement limitées ?", "Libérons uses generous server-side safeguards against abnormal repeated original transfers. Normal use should not require you to manage a daily counter. If unusually intensive activity is detected, original recovery may be temporarily slowed or limited while your protected files remain safe.", "Libérons utilise des protections serveur généreuses contre les transferts répétés anormaux d’originaux. Une utilisation normale ne devrait pas vous obliger à gérer un compteur quotidien. Si une activité exceptionnellement intensive est détectée, la récupération d’originaux peut être temporairement ralentie ou limitée, sans affecter la protection de vos fichiers.", "limit limite restore restauration intensive abus download télécharger original"),
        item("signin", "account", "Do I need an account?", "Ai-je besoin d’un compte ?", "Yes. Your account securely associates your protected media, storage allowance, devices and subscription state with you.", "Oui. Votre compte associe de manière sécurisée vos médias protégés, votre espace, vos appareils et l’état de votre abonnement.", "account compte login connexion inscription sign in"),
        item("signout", "account", "Does signing out delete my protected files?", "Se déconnecter supprime-t-il mes fichiers protégés ?", "No. Signing out removes the active session from that device; it does not by itself delete protected cloud media from your account.", "Non. La déconnexion retire la session active de cet appareil ; elle ne supprime pas à elle seule les médias protégés de votre compte cloud.", "logout signout déconnexion fichiers supprimer"),
        item("devices", "account", "Can I use Libérons on another iPhone?", "Puis-je utiliser Libérons sur un autre iPhone ?", "You can sign in on another supported device. Device and free-tier protections may apply to prevent abuse, while paid account entitlements remain tied to the account.", "Vous pouvez vous connecter sur un autre appareil compatible. Des protections liées aux appareils et au forfait gratuit peuvent s’appliquer pour éviter les abus, tandis que les droits d’un compte payant restent liés au compte.", "device appareil multiple iphone autre téléphone free gratuit"),
        item("free-tier", "billing", "How does free storage work?", "Comment fonctionne le stockage gratuit ?", "Eligible accounts can receive the free storage allowance shown by Libérons. Eligibility is protected against repeated account creation or device abuse, so creating multiple accounts does not guarantee multiple free allowances.", "Les comptes éligibles peuvent recevoir l’espace gratuit affiché par Libérons. L’éligibilité est protégée contre la création répétée de comptes ou les abus par appareil : créer plusieurs comptes ne garantit donc pas plusieurs espaces gratuits.", "free gratuit 2 gb go offre essai multiple compte abuse"),
        item("subscription", "billing", "Where do I subscribe or manage my plan?", "Où puis-je m’abonner ou gérer mon forfait ?", "Libérons billing is handled through the official Libérons website and account controls. The app reflects the storage entitlement associated with your account.", "La facturation Libérons est gérée depuis le site officiel Libérons et les contrôles de votre compte. L’app reflète ensuite l’espace associé à votre compte.", "subscription abonnement plan forfait payer payment paiement website site"),
        item("uninstall", "billing", "Does deleting the app cancel my subscription?", "Supprimer l’app annule-t-il mon abonnement ?", "No. Uninstalling Libérons or signing out does not cancel a subscription. Use the official account and billing controls to manage or cancel a paid plan.", "Non. Désinstaller Libérons ou vous déconnecter n’annule pas un abonnement. Utilisez les contrôles officiels du compte et de facturation pour gérer ou annuler un forfait payant.", "delete app uninstall désinstaller cancel annuler abonnement subscription"),
        item("payment-failed", "billing", "What happens if a subscription payment fails?", "Que se passe-t-il si le paiement de mon abonnement échoue ?", "New storage uploads are paused during the payment grace period. A limited amount of original recovery remains available during the grace period. If the account is not regularized by the end of that period, original restores are blocked until payment is resolved. Protected files are not deleted simply because a payment failed.", "Les nouveaux envois vers le stockage sont suspendus pendant la période de grâce de paiement. Une quantité limitée de récupération d’originaux reste disponible durant cette période. Si le compte n’est pas régularisé à la fin de celle-ci, les restaurations d’originaux sont bloquées jusqu’à régularisation. Les fichiers protégés ne sont pas supprimés simplement parce qu’un paiement a échoué.", "payment failed paiement échoué grace grâce 7 jours restore bloqué facture carte"),
        item("privacy", "security", "Can Libérons see or sell my photos?", "Libérons peut-il vendre mes photos ?", "Libérons processes the media needed to provide the protection, storage and recovery features you request. Libérons does not sell your photos or videos or use them for targeted advertising.", "Libérons traite les médias nécessaires pour fournir les fonctions de protection, stockage et récupération que vous demandez. Libérons ne vend pas vos photos ou vidéos et ne les utilise pas pour de la publicité ciblée.", "privacy confidentialité vendre sell ads publicité photos données"),
        item("permissions", "security", "Why does Libérons need Photos access?", "Pourquoi Libérons a-t-il besoin d’accéder à Photos ?", "Photos access is required to select originals for protection and, when you request it, to restore media or remove confirmed protected local copies. You can review Photos permissions in iPhone Settings.", "L’accès à Photos est nécessaire pour sélectionner les originaux à protéger et, lorsque vous le demandez, restaurer des médias ou retirer des copies locales dont la protection est confirmée. Vous pouvez contrôler cette autorisation dans les réglages de l’iPhone.", "permission autorisation photos access accès settings réglages"),
        item("limited-photos", "troubleshooting", "Why can Libérons not see all my photos?", "Pourquoi Libérons ne voit-il pas toutes mes photos ?", "Check the Photos permission for Libérons. If iOS is set to Limited Access, Libérons can only work with the photos you selected. You can change this in iPhone Settings.", "Vérifiez l’autorisation Photos de Libérons. Si iOS est réglé sur Accès limité, Libérons ne peut travailler qu’avec les photos que vous avez sélectionnées. Vous pouvez modifier ce choix dans les réglages de l’iPhone.", "missing photos manque photo accès limité limited permission"),
        item("slow", "troubleshooting", "Why is a backup slow?", "Pourquoi la sauvegarde est-elle lente ?", "Speed depends on your connection, media size, whether originals must first download from iCloud, and iOS power or thermal conditions. Large videos naturally take longer. Libérons prioritizes reliable confirmed uploads over marking a file protected too early.", "La vitesse dépend de votre connexion, de la taille des médias, du téléchargement éventuel des originaux depuis iCloud et des conditions d’alimentation ou de température d’iOS. Les grandes vidéos prennent naturellement plus de temps. Libérons privilégie une sauvegarde confirmée plutôt que de déclarer un fichier protégé trop tôt.", "slow lent lente vitesse upload vidéo icloud thermal température batterie"),
        item("offline", "troubleshooting", "What happens if my connection drops during a backup?", "Que se passe-t-il si ma connexion coupe pendant une sauvegarde ?", "The affected upload can fail or pause and be retried. Libérons does not mark the item protected unless the cloud copy is confirmed.", "L’envoi concerné peut échouer ou se mettre en pause puis être réessayé. Libérons ne marque pas l’élément comme protégé tant que la copie cloud n’est pas confirmée.", "offline hors ligne internet coupure connection connexion retry"),
        item("support", "troubleshooting", "What should I send to support if I have a problem?", "Que dois-je envoyer au support en cas de problème ?", "Describe what you were doing, what you expected, what happened, and any error shown. A screenshot can help. Never send your password, verification codes, API keys or full card number.", "Décrivez ce que vous faisiez, ce que vous attendiez, ce qui s’est produit et le message d’erreur affiché. Une capture d’écran peut aider. N’envoyez jamais votre mot de passe, vos codes de vérification, vos clés API ni votre numéro complet de carte.", "support aide problème screenshot capture erreur password mot de passe carte" )
    ] }

    private var filteredItems: [FAQItem] {
        let query = normalize(searchText)
        return items.filter { entry in
            guard selectedCategory == "all" || entry.category == selectedCategory else { return false }
            guard !query.isEmpty else { return true }
            let searchable = normalize([entry.questionEN, entry.questionFR, entry.answerEN, entry.answerFR, entry.keywords, categoryTitle(entry.category)].joined(separator: " "))
            let tokens = query.split(separator: " ").map(String.init).filter { $0.count > 1 }
            return searchable.contains(query) || (!tokens.isEmpty && tokens.allSatisfy { searchable.contains($0) })
        }
    }

    private var groupedCategories: [String] { categories.map(\.0).filter { $0 != "all" && filteredItems.contains(where: { $0.category == $0 }) } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(language.text("Libérons Support", "Assistance Libérons"), systemImage: "message.badge.fill").font(.headline).foregroundStyle(.blue)
                    Text(language.text("Search the complete help library or browse by topic. Search checks questions, answers and related terms in both French and English.", "Recherchez dans toute l’aide ou parcourez-la par thème. La recherche analyse les questions, les réponses et les termes associés en français comme en anglais.")).font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.0) { category in
                            Button { selectedCategory = category.0 } label: {
                                Text(language.text(category.1, category.2)).font(.subheadline.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 8).background(selectedCategory == category.0 ? Color.blue : Color.secondary.opacity(0.12), in: Capsule()).foregroundStyle(selectedCategory == category.0 ? Color.white : Color.primary)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 2)
                }
            }
            if filteredItems.isEmpty {
                Section {
                    ContentUnavailableView(language.text("No answer found", "Aucune réponse trouvée"), systemImage: "magnifyingglass", description: Text(language.text("Try another word, choose All, or contact Libérons Support.", "Essayez un autre mot, choisissez Tout ou contactez l’assistance Libérons.")))
                }
            } else {
                ForEach(categories.filter { $0.0 != "all" && filteredItems.contains(where: { item in item.category == $0.0 }) }, id: \.0) { category in
                    Section(language.text(category.1, category.2)) {
                        ForEach(filteredItems.filter { $0.category == category.0 }) { entry in
                            faq(language.text(entry.questionEN, entry.questionFR), language.text(entry.answerEN, entry.answerFR))
                        }
                    }
                }
            }
            Section(language.text("Still need help?", "Encore besoin d’aide ?")) {
                LiberonsExternalRow(icon: "envelope.fill", title: "support@liberons.com", subtitle: language.text("Email Libérons Support", "Écrire à l’assistance Libérons")) { emailSupport() }
                LiberonsExternalRow(icon: "questionmark.circle.fill", title: language.text("Help Center", "Centre d’aide"), subtitle: language.text("More support resources", "Plus de ressources d’assistance")) { open(.support) }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: language.text("Search backup, billing, restore…", "Rechercher sauvegarde, paiement, restauration…"))
        .navigationTitle(language.text("Help & support", "Aide et support"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(_ id: String, _ category: String, _ enQ: String, _ frQ: String, _ enA: String, _ frA: String, _ keywords: String) -> FAQItem { FAQItem(id: id, category: category, questionEN: enQ, questionFR: frQ, answerEN: enA, answerFR: frA, keywords: keywords) }
    @ViewBuilder private func faq(_ question: String, _ answer: String) -> some View { DisclosureGroup(question) { Text(answer).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 6).textSelection(.enabled) } }
    private func normalize(_ value: String) -> String { value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased().replacingOccurrences(of: "’", with: "'") }
    private func categoryTitle(_ id: String) -> String { categories.first(where: { $0.0 == id }).map { "\($0.1) \($0.2)" } ?? id }
    private func open(_ destination: LiberonsWebDestination) { guard let url = destination.url(for: language.language) else { return }; UIApplication.shared.open(url) }
    private func emailSupport() { guard let url = URL(string: "mailto:support@liberons.com?subject=Lib%C3%A9rons%20Support") else { return }; UIApplication.shared.open(url) }
}

struct LiberonsAboutView: View {
    @ObservedObject var language: LanguageStore
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack { RoundedRectangle(cornerRadius: 28).fill(Color.blue.gradient).frame(width: 92, height: 92); Image(systemName: "icloud.and.arrow.up.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white) }
                VStack(spacing: 6) { Text("Libérons").font(.system(size: 34, weight: .bold, design: .rounded)); Text(language.text("Keep your memories. Free your space.", "Gardez vos souvenirs. Libérez votre espace.")).font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                aboutCard {
                    Text(language.text("Your memories, protected. Your space, reclaimed.", "Vos souvenirs protégés. Votre espace retrouvé.")).font(.title3.bold())
                    Text(language.text("Libérons securely protects your photos and videos in the cloud so you can reclaim space on your iPhone without giving up the memories that matter.", "Libérons protège vos photos et vidéos dans le cloud afin de vous permettre de récupérer de l’espace sur votre iPhone, sans renoncer aux souvenirs qui comptent."))
                    Divider()
                    aboutPoint("checkmark.icloud.fill", language.text("Protection you can verify", "Une protection vérifiable"), language.text("A media item is considered protected only after its cloud copy has been confirmed.", "Un média n’est considéré comme protégé qu’après confirmation de sa copie dans le cloud."))
                    aboutPoint("iphone", language.text("You remain in control", "Vous gardez le contrôle"), language.text("Backing up and removing a local copy are always separate actions.", "La sauvegarde et le retrait d’une copie locale restent toujours deux actions distinctes."))
                    aboutPoint("arrow.down.to.line.compact", language.text("Access when you need it", "Vos souvenirs, quand vous en avez besoin"), language.text("Your protected memories remain available in your Libérons Library, subject to your account access.", "Vos souvenirs protégés restent accessibles dans votre Bibliothèque Libérons, selon l’état de votre compte."))
                }
                aboutCard {
                    Text(language.text("Libérons online", "Libérons en ligne")).font(.headline)
                    LiberonsExternalRow(icon: "globe", title: language.text("Visit Libérons", "Découvrir Libérons"), subtitle: language.text("Official website", "Site officiel")) { open(.home) }
                }
                aboutCard { HStack { Text(language.text("App version", "Version de l’app")); Spacer(); Text(version).foregroundStyle(.secondary) }; Divider(); HStack { Text(language.text("Service operator", "Exploitant du service")); Spacer(); Text("Freddy Mboma").foregroundStyle(.secondary) }; Divider(); HStack { Text(language.text("Based in", "Établi au")); Spacer(); Text("Canada").foregroundStyle(.secondary) } }
                Text(language.text("Libérons · Built to protect what matters and give your space back.", "Libérons · Protéger ce qui compte. Retrouver votre espace.")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("© 2026 Libérons").font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
            }.padding(24)
        }.background(LiberonsTheme.canvas).navigationTitle(language.text("About Libérons", "À propos de Libérons")).navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func aboutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 14) { content() }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous)) }
    @ViewBuilder private func aboutPoint(_ icon: String, _ title: String, _ detail: String) -> some View { HStack(alignment: .top, spacing: 12) { Image(systemName: icon).foregroundStyle(.blue).frame(width: 24).padding(.top, 2); VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.bold()); Text(detail).font(.subheadline).foregroundStyle(.secondary) } } }
    private func open(_ destination: LiberonsWebDestination) { guard let url = destination.url(for: language.language) else { return }; UIApplication.shared.open(url) }
    private var version: String { let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"; let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"; return "\(version) (\(build))" }
}