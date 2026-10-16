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
                    Button(language.text("Open iOS Settings", "Ouvrir les réglages iOS")) { openSettings() }
                }
            } footer: {
                Text(language.text("Libérons only uses notifications that help you protect memories or free space.", "Libérons utilise uniquement les notifications utiles pour protéger vos souvenirs ou libérer de l’espace."))
            }

            Section(language.text("Backup", "Sauvegarde")) {
                notificationToggle(language.text("Backup completed", "Sauvegarde terminée"), icon: "checkmark.circle.fill", isOn: $backupComplete)
                notificationToggle(language.text("Ready to free space", "Espace prêt à être libéré"), icon: "iphone.and.arrow.forward", isOn: $readyToFree)
                notificationToggle(language.text("Backup interrupted", "Sauvegarde interrompue"), icon: "exclamationmark.triangle.fill", isOn: $backupInterrupted)
            }

            Section(language.text("Storage", "Stockage")) {
                notificationToggle(language.text("Libérons storage warnings", "Alertes de stockage Libérons"), icon: "externaldrive.badge.exclamationmark", isOn: $storageWarnings)
                notificationToggle(language.text("Backup reminder", "Rappel de sauvegarde"), icon: "clock.badge", isOn: $backupReminder)
            }

            if authorization == .authorized || authorization == .provisional || authorization == .ephemeral {
                Section { Button(language.text("Manage in iOS Settings", "Gérer dans les réglages iOS")) { openSettings() } }
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
                Text(language.text("iOS notifications", "Notifications iOS"))
                Text(statusText).font(.caption).foregroundStyle(Color.secondary)
            }
            Spacer()
        }
    }

    private func notificationToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Label(title, systemImage: icon).foregroundStyle(Color.primary) }
            .disabled(authorization == .denied)
    }

    private var statusText: String {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return language.text("Allowed", "Autorisées")
        case .denied: return language.text("Disabled in iOS Settings", "Désactivées dans les réglages iOS")
        case .notDetermined: return language.text("Not configured", "Non configurées")
        @unknown default: return "—"
        }
    }

    private func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func requestPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct LiberonsPrivacySecurityView: View {
    @ObservedObject var language: LanguageStore
    @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "photo.stack.fill").foregroundStyle(Color.blue).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.text("Photo library access", "Accès à la photothèque"))
                        Text(photoAccessText).font(.caption).foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Image(systemName: photoStatus == .authorized ? "checkmark.circle.fill" : "chevron.right")
                        .foregroundStyle(photoStatus == .authorized ? Color.green : Color.secondary.opacity(0.45))
                }
                .contentShape(Rectangle())
                .onTapGesture { openAppSettings() }
            } footer: {
                Text(language.text("Libérons needs photo access to protect the memories you choose and to free local space only when you ask.", "Libérons a besoin de l’accès aux photos pour protéger les souvenirs que vous choisissez et libérer l’espace local uniquement à votre demande."))
            }

            Section(language.text("Protection", "Protection")) {
                Label(language.text("Protected originals are verified before they become eligible for local removal.", "Les originaux protégés sont vérifiés avant de pouvoir être supprimés localement."), systemImage: "checkmark.shield.fill")
                Label(language.text("Libérons never removes an original from this iPhone without your action.", "Libérons ne supprime jamais un original de cet iPhone sans votre action."), systemImage: "hand.raised.fill")
            }

            Section(language.text("Account security", "Sécurité du compte")) {
                Label(language.text("Your Libérons session is stored securely on this device.", "Votre session Libérons est conservée de manière sécurisée sur cet appareil."), systemImage: "lock.fill")
                Button(language.text("Open Libérons settings", "Ouvrir les réglages de Libérons")) { openAppSettings() }
            }
        }
        .navigationTitle(language.text("Privacy & security", "Confidentialité et sécurité"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    }

    private var photoAccessText: String {
        switch photoStatus {
        case .authorized: return language.text("Full access", "Accès complet")
        case .limited: return language.text("Limited access", "Accès limité")
        case .denied, .restricted: return language.text("Access disabled", "Accès désactivé")
        case .notDetermined: return language.text("Not configured", "Non configuré")
        @unknown default: return "—"
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct LiberonsHelpSupportView: View {
    @ObservedObject var language: LanguageStore

    var body: some View {
        List {
            Section {
                Label(language.text("Libérons protects a copy first. Nothing is removed locally until protection is verified and you choose to free space.", "Libérons protège d’abord une copie. Rien n’est supprimé localement tant que la protection n’est pas vérifiée et que vous n’avez pas choisi de libérer l’espace."), systemImage: "shield.checkered")
            }
            Section(language.text("Common questions", "Questions fréquentes")) {
                DisclosureGroup(language.text("What happens when I free space?", "Que se passe-t-il quand je libère de l’espace ?")) {
                    Text(language.text("Only eligible originals already protected by Libérons are selected for local removal. Your protected copy remains in your Libérons library.", "Seuls les originaux éligibles déjà protégés par Libérons sont sélectionnés pour la suppression locale. Votre copie protégée reste dans votre bibliothèque Libérons."))
                }
                DisclosureGroup(language.text("Can I keep my originals on my iPhone?", "Puis-je garder mes originaux sur mon iPhone ?")) {
                    Text(language.text("Yes. Backup and freeing space are separate actions.", "Oui. La sauvegarde et la libération d’espace sont deux actions distinctes."))
                }
                DisclosureGroup(language.text("Why does Libérons need photo access?", "Pourquoi Libérons a besoin d’accéder aux photos ?")) {
                    Text(language.text("It is required to read the photos and videos you choose to protect and, only with your confirmation, request their local removal.", "Cet accès est nécessaire pour lire les photos et vidéos que vous choisissez de protéger et, uniquement avec votre confirmation, demander leur suppression locale."))
                }
            }
            Section(language.text("Diagnostics", "Diagnostic")) {
                HStack { Text(language.text("App version", "Version de l’app")); Spacer(); Text(appVersion).foregroundStyle(Color.secondary) }
                HStack { Text(language.text("Build", "Build")); Spacer(); Text(buildNumber).foregroundStyle(Color.secondary) }
            }
        }
        .navigationTitle(language.text("Help & support", "Aide et support"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    private var buildNumber: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }
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
                Text("Libérons").font(.system(size: 34, weight: .bold, design: .rounded))
                Text(language.text("Keep your memories. Free your space.", "Gardez vos souvenirs. Libérez votre espace.")).font(.headline).foregroundStyle(Color.secondary).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 14) {
                    Text(language.text("Libérons is designed to make photo and video storage simple: protect your memories first, verify them, then choose when you want to reclaim space on your iPhone.", "Libérons est conçu pour simplifier le stockage de vos photos et vidéos : protégez d’abord vos souvenirs, vérifiez-les, puis choisissez quand vous souhaitez récupérer de l’espace sur votre iPhone."))
                    Divider()
                    HStack { Text(language.text("Version", "Version")); Spacer(); Text(version).foregroundStyle(Color.secondary) }
                }
                .padding(20)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24))
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(language.text("About Libérons", "À propos de Libérons"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var version: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
