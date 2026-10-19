import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var language: LanguageStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LiberonsNotificationSettingsView(language: language)
                } label: {
                    settingsRow(
                        icon: "bell.badge.fill",
                        title: language.text("Notifications", "Notifications"),
                        subtitle: language.text("Backup and storage alerts", "Alertes de sauvegarde et de stockage")
                    )
                }

                NavigationLink {
                    LiberonsPrivacySecurityView(language: language)
                } label: {
                    settingsRow(
                        icon: "hand.raised.square.fill",
                        title: language.text("Privacy & security", "Confidentialité et sécurité"),
                        subtitle: language.text("Permissions, privacy and legal documents", "Autorisations, confidentialité et documents juridiques")
                    )
                }
            }

            Section {
                NavigationLink {
                    LiberonsHelpSupportView(language: language)
                } label: {
                    settingsRow(
                        icon: "questionmark.circle.fill",
                        title: language.text("Help & support", "Aide et support"),
                        subtitle: language.text("Answers and Libérons Support", "Réponses et assistance Libérons")
                    )
                }

                NavigationLink {
                    LiberonsAboutView(language: language)
                } label: {
                    settingsRow(
                        icon: "info.circle.fill",
                        title: language.text("About Libérons", "À propos de Libérons"),
                        subtitle: language.text("App information and version", "Informations et version de l’app")
                    )
                }
            }
        }
        .navigationTitle(language.text("Settings", "Réglages"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
