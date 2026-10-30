import SwiftUI
import AVKit

struct AppSettingsView: View {
    @ObservedObject var language: LanguageStore

    var body: some View {
        List {
            Section {
                NavigationLink { ProtectedFilesView(language: language) } label: {
                    settingsRow(icon: "doc.fill", title: language.text("Protected files", "Fichiers protégés"), subtitle: language.text("Protect documents and files in Libérons Cloud", "Protégez vos documents et fichiers dans Libérons Cloud"))
                }
                NavigationLink { LiberonsNotificationSettingsView(language: language) } label: {
                    settingsRow(icon: "bell.badge.fill", title: language.text("Notifications", "Notifications"), subtitle: language.text("Backup and storage alerts", "Alertes de sauvegarde et de stockage"))
                }
                NavigationLink { LiberonsPrivacySecurityView(language: language) } label: {
                    settingsRow(icon: "hand.raised.square.fill", title: language.text("Privacy & security", "Confidentialité et sécurité"), subtitle: language.text("Permissions, privacy and legal documents", "Autorisations, confidentialité et documents juridiques"))
                }
            }

            Section {
                NavigationLink { LiberonsTutorialView(language: language) } label: {
                    settingsRow(icon: "play.rectangle.fill", title: language.text("How to use Libérons", "Comment utiliser Libérons"), subtitle: language.text("Watch the official Libérons tutorial", "Regardez le tutoriel officiel Libérons"))
                }
                NavigationLink { LiberonsHelpSupportView(language: language) } label: {
                    settingsRow(icon: "questionmark.circle.fill", title: language.text("Help & support", "Aide et support"), subtitle: language.text("Answers and Libérons Support", "Réponses et assistance Libérons"))
                }
                NavigationLink { LiberonsAboutView(language: language) } label: {
                    settingsRow(icon: "info.circle.fill", title: language.text("About Libérons", "À propos de Libérons"), subtitle: language.text("App information and version", "Informations et version de l’app"))
                }
            }
        }
        .navigationTitle(language.text("Settings", "Réglages"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }
}

struct LiberonsTutorialView: View {
    @ObservedObject var language: LanguageStore
    @State private var player: AVPlayer?
    @State private var showingFullscreen = false

    private var tutorialURL: URL {
        let code = language.language == .english ? "en" : "fr"
        return URL(string: "https://liberons.com/api/tutorial?lang=\(code)")!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(language.text("OFFICIAL TUTORIAL", "TUTORIEL OFFICIEL")).font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(.blue)
                    Text(language.text("Learn Libérons, step by step.", "Découvrez Libérons, étape par étape.")).font(.largeTitle.bold())
                    Text(language.text("See how to protect your content, use Libérons Cloud and safely reclaim space on your iPhone.", "Découvrez comment protéger vos contenus, utiliser Libérons Cloud et récupérer de l’espace sur votre iPhone en toute sécurité.")).foregroundStyle(.secondary)
                }
                Group {
                    if let player {
                        ZStack(alignment: .topTrailing) {
                            VideoPlayer(player: player).aspectRatio(16/9, contentMode: .fit)
                            Button { showingFullscreen = true } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.black.opacity(0.68), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .accessibilityLabel(language.text("Full screen", "Plein écran"))
                        }
                    }
                    else { ZStack { RoundedRectangle(cornerRadius: 18).fill(Color.secondary.opacity(0.12)); ProgressView() }.aspectRatio(16/9, contentMode: .fit) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(language.text("The video is streamed securely and is not stored inside the app, keeping Libérons lightweight.", "La vidéo est diffusée en ligne et n’est pas stockée dans l’app, afin de garder Libérons légère.")).font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(LiberonsTheme.canvas.ignoresSafeArea())
        .navigationTitle(language.text("Tutorial", "Tutoriel"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if player == nil { player = AVPlayer(url: tutorialURL) } }
        .onDisappear { player?.pause(); player = nil }
        .onChange(of: language.language) { _, _ in player?.pause(); player = AVPlayer(url: tutorialURL) }
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let player {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VideoPlayer(player: player).ignoresSafeArea()
                    VStack {
                        HStack {
                            Spacer()
                            Button { showingFullscreen = false } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.black.opacity(0.65), in: Circle())
                            }
                            .padding()
                            .accessibilityLabel(language.text("Close full screen", "Fermer le plein écran"))
                        }
                        Spacer()
                    }
                }
                .statusBarHidden(true)
            }
        }
    }
}
