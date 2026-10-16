import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var auth = AuthStore()
    @StateObject private var language = LanguageStore()

    var body: some View {
        Group {
            if auth.isLoading { ProgressView() }
            else if auth.isAuthenticated { MainAppView(auth: auth, language: language) }
            else { SignInView(auth: auth, language: language) }
        }
    }
}

private struct SignInView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var language: LanguageStore
    @State private var email = ""
    @State private var password = ""
    @State private var signingIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                HStack { Spacer(); Menu(language.language.title) { ForEach(LanguageStore.Language.allCases) { item in Button(item.title) { language.language = item } } }.buttonStyle(.bordered) }
                Spacer()
                Text("Libérons").font(.system(size: 44, weight: .bold, design: .rounded))
                Text(language.text("Keep your memories. Free your space.", "Gardez vos souvenirs. Libérez votre espace.")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                TextField(language.text("Email", "E-mail"), text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).padding().background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                SecureField(language.text("Password", "Mot de passe"), text: $password).padding().background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                if let error = auth.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                Button { signingIn = true; Task { await auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password); signingIn = false } } label: {
                    Group { if signingIn { ProgressView().tint(.white) } else { Text(language.text("Sign in", "Se connecter")).fontWeight(.semibold) } }.frame(maxWidth: .infinity).frame(height: 54)
                }.buttonStyle(.borderedProminent).disabled(signingIn || email.isEmpty || password.isEmpty)
                Spacer()
            }.padding(24)
        }
    }
}

private struct MainAppView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var language: LanguageStore
    @StateObject private var analyzer = PhotoLibraryAnalyzer()
    @StateObject private var preferences = BackupPreferences()
    @StateObject private var backup = BackupEngine()
    @StateObject private var cloud = CloudStorageSummary()

    var body: some View {
        TabView {
            DashboardView(analyzer: analyzer, cloud: cloud, language: language).tabItem { Label(language.text("Home", "Accueil"), systemImage: "house.fill") }
            BackupView(analyzer: analyzer, preferences: preferences, backup: backup, language: language).tabItem { Label(language.text("Backup", "Sauvegarde"), systemImage: "icloud.and.arrow.up.fill") }
            ProtectedLibraryView(language: language).tabItem { Label(language.text("Library", "Bibliothèque"), systemImage: "photo.on.rectangle.angled") }
            AccountView(auth: auth, language: language).tabItem { Label(language.text("Account", "Compte"), systemImage: "person.crop.circle.fill") }
        }.task { async let scan: Void = analyzer.refreshIfNeeded(); async let summary: Void = cloud.refresh(); _ = await (scan, summary) }
    }
}

private struct DashboardView: View {
    @ObservedObject var analyzer: PhotoLibraryAnalyzer
    @ObservedObject var cloud: CloudStorageSummary
    @ObservedObject var language: LanguageStore

    private var totalItems: Int { analyzer.photoCount + analyzer.videoCount }
    private var cloudProgress: Double { guard cloud.quotaBytes > 0 else { return 0 }; return min(1, Double(cloud.protectedBytes + cloud.pendingBytes) / Double(cloud.quotaBytes)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Libérons").font(.system(size: 38, weight: .bold, design: .rounded))
                        Text(language.text("Your memories, without the storage stress.", "Vos souvenirs, sans le stress du stockage.")).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Label(language.text("Your photo library", "Votre photothèque"), systemImage: "photo.stack.fill").font(.headline)
                            Spacer(); if analyzer.isScanning { ProgressView() }
                        }
                        Text(analyzer.formattedSize).font(.system(size: 50, weight: .bold, design: .rounded)).minimumScaleFactor(0.75)
                        Text(language.text("across \(totalItems.formatted()) photos and videos", "répartis sur \(totalItems.formatted()) photos et vidéos")).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            StatTile(icon: "photo.fill", value: analyzer.photoCount.formatted(), title: "Photos")
                            StatTile(icon: "video.fill", value: analyzer.videoCount.formatted(), title: language.text("Videos", "Vidéos"))
                        }
                    }.premiumCard()

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("Libérons Cloud", systemImage: "icloud.fill").font(.headline).foregroundStyle(.blue)
                            Spacer()
                            Text(formatBytes(cloud.protectedBytes)).font(.headline.bold())
                        }
                        ProgressView(value: cloudProgress).tint(.blue).scaleEffect(x: 1, y: 1.8)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(language.text("Protected", "Protégé")).font(.caption).foregroundStyle(.secondary)
                                Text("\(cloud.protectedCount.formatted()) " + language.text("memories", "souvenirs")).font(.subheadline.bold())
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(language.text("Cloud plan", "Forfait cloud")).font(.caption).foregroundStyle(.secondary)
                                Text(cloud.quotaBytes > 0 ? formatBytes(cloud.quotaBytes) : "—").font(.subheadline.bold())
                            }
                        }
                        if cloud.pendingBytes > 0 { Label(formatBytes(cloud.pendingBytes) + " " + language.text("being protected", "en cours de protection"), systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.orange) }
                    }.premiumCard()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            ZStack { Circle().fill((cloud.protectedCount > 0 ? Color.green : Color.orange).opacity(0.13)).frame(width: 46, height: 46); Image(systemName: cloud.protectedCount > 0 ? "checkmark.shield.fill" : "shield.lefthalf.filled").foregroundStyle(cloud.protectedCount > 0 ? .green : .orange).font(.title3) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cloud.protectedCount > 0 ? language.text("Protection active", "Protection active") : language.text("Ready to protect", "Prêt à protéger")).font(.headline)
                                Text(cloud.protectedCount > 0 ? language.text("Your protected memories are safely stored in Libérons Cloud.", "Vos souvenirs protégés sont conservés dans Libérons Cloud.") : language.text("Choose your oldest memories or select exactly what you want to protect.", "Choisissez vos souvenirs les plus anciens ou sélectionnez exactement ce que vous voulez protéger.")).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if let date = cloud.lastProtectedAt {
                            Divider()
                            HStack { Text(language.text("Last protection", "Dernière protection")).foregroundStyle(.secondary); Spacer(); Text(date.formatted(date: .abbreviated, time: .shortened)).fontWeight(.semibold) }.font(.caption)
                        }
                    }.premiumCard()

                    Button {
                        Task { async let a: Void = analyzer.scanNow(); async let b: Void = cloud.refresh(); _ = await (a, b) }
                    } label: {
                        HStack { Spacer(); if analyzer.isScanning || cloud.isLoading { ProgressView() }; Label(language.text("Refresh dashboard", "Actualiser le tableau de bord"), systemImage: "arrow.clockwise"); Spacer() }.frame(height: 38)
                    }.buttonStyle(.bordered).disabled(analyzer.isScanning || cloud.isLoading)
                }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 110)
            }.background(Color(uiColor: .systemGroupedBackground)).toolbar(.hidden, for: .navigationBar)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

private struct BackupView: View {
    @ObservedObject var analyzer: PhotoLibraryAnalyzer
    @ObservedObject var preferences: BackupPreferences
    @ObservedObject var backup: BackupEngine
    @ObservedObject var language: LanguageStore
    @State private var showInfo = false
    private var totalItems: Int { analyzer.photoCount + analyzer.videoCount }
    private var protectedBytes: Int64 { Int64(Double(analyzer.estimatedBytes) * Double(preferences.backupPercent) / 100) }
    private var removableBytes: Int64 { Int64(Double(protectedBytes) * Double(preferences.removalPercent) / 100) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) { Text(language.text("Free your space", "Libérez votre espace")).font(.system(size: 34, weight: .bold, design: .rounded)); Text(language.text("Protect first. Remove locally only after verification.", "Protégez d'abord. Retirez localement uniquement après vérification.")).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 18) {
                        Label(language.text("1. Protect in Libérons Cloud", "1. Protéger dans Libérons Cloud"), systemImage: "icloud.and.arrow.up.fill").font(.headline).foregroundStyle(.blue)
                        HStack(alignment: .firstTextBaseline) { Text(formatBytes(protectedBytes)).font(.system(size: 40, weight: .bold, design: .rounded)); Spacer(); Text("\(preferences.backupPercent)%").font(.title3.bold()).foregroundStyle(.blue) }
                        Text(language.text("about \(preferences.selectedCount(total: totalItems).formatted()) items", "environ \(preferences.selectedCount(total: totalItems).formatted()) éléments")).foregroundStyle(.secondary)
                        PercentagePicker(selection: $preferences.backupPercent, choices: BackupPreferences.choices)
                    }.premiumCard()
                    BackupQueueView(backup: backup, preferences: preferences, analyzer: analyzer, language: language)
                    VStack(alignment: .leading, spacing: 18) {
                        HStack { Label(language.text("2. Free space on this iPhone", "2. Libérer de l'espace sur cet iPhone"), systemImage: "iphone.and.arrow.forward").font(.headline).foregroundStyle(.green); Spacer(); Button { showInfo = true } label: { Image(systemName: "info.circle") } }
                        HStack(alignment: .firstTextBaseline) { Text(formatBytes(removableBytes)).font(.system(size: 40, weight: .bold, design: .rounded)); Spacer(); Text("\(preferences.removalPercent)%").font(.title3.bold()).foregroundStyle(.green) }
                        PercentagePicker(selection: $preferences.removalPercent, choices: BackupPreferences.choices)
                        Text(language.text("This percentage is applied only to originals already verified as protected.", "Ce pourcentage s'applique uniquement aux originaux déjà vérifiés comme protégés.")).font(.caption).foregroundStyle(.secondary)
                    }.premiumCard()
                    FreeSpaceView(preferences: preferences, language: language)
                    VStack(alignment: .leading, spacing: 16) {
                        Text(language.text("Single-item verification", "Vérification d'un élément")).font(.headline)
                        if let name = backup.selectedFilename { HStack(spacing: 14) { LocalAssetThumbnail(localIdentifier: backup.selectedLocalIdentifier, isVideo: backup.selectedIsVideo).frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 18)); VStack(alignment: .leading, spacing: 5) { Text(name).font(.subheadline.bold()).lineLimit(2); Text(backup.selectedIsVideo ? language.text("Video", "Vidéo") : "Photo").font(.caption).foregroundStyle(.secondary); if backup.selectedBytes > 0 { Text(ByteCountFormatter.string(fromByteCount: backup.selectedBytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }; if let date = backup.selectedCreationDate { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) } } } }
                        Button { Task { await backup.backupOneOldestAsset() } } label: { HStack { Spacer(); if backup.isRunning { ProgressView().tint(.white) }; Text(backup.selectedFilename == nil ? language.text("Preview oldest item", "Voir l'élément le plus ancien") : language.text("Protect this exact item", "Protéger exactement cet élément")).fontWeight(.semibold); Spacer() }.frame(height: 36) }.buttonStyle(.borderedProminent).disabled(backup.isRunning || !analyzer.canReadLibrary)
                        if !backup.message.isEmpty { Text(backup.message).font(.caption).foregroundStyle(backup.message.contains("✓") ? .green : .secondary) }
                    }.premiumCard()
                }.padding(.horizontal, 20).padding(.bottom, 110)
            }.toolbar(.hidden, for: .navigationBar)
        }.alert(language.text("Freeing iPhone space", "Libérer l'espace de l'iPhone"), isPresented: $showInfo) { Button("OK", role: .cancel) {} } message: { Text(language.text("Libérons only proposes local removal for media already marked Protected in the cloud. iOS still asks for confirmation.", "Libérons ne propose le retrait local que pour les médias déjà marqués Protégé dans le cloud. iOS demande toujours votre confirmation.")) }
    }
    private func formatBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

private struct LocalAssetThumbnail: View {
    let localIdentifier: String?; let isVideo: Bool; @State private var image: UIImage?
    var body: some View { ZStack { Rectangle().fill(Color.secondary.opacity(0.10)); if let image { Image(uiImage: image).resizable().scaledToFill() } else { Image(systemName: isVideo ? "video.fill" : "photo.fill").foregroundStyle(.secondary) }; if isVideo { Image(systemName: "play.fill").padding(7).background(.ultraThinMaterial, in: Circle()) } }.clipped().task(id: localIdentifier) { guard let id = localIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }; let options = PHImageRequestOptions(); options.deliveryMode = .highQualityFormat; options.resizeMode = .fast; options.isNetworkAccessAllowed = true; PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options) { value, _ in if let value { Task { @MainActor in image = value } } } } }
}

private struct PercentagePicker: View {
    @Binding var selection: Int; let choices: [Int]
    var body: some View { HStack(spacing: 7) { ForEach(choices, id: \.self) { value in Button("\(value)%") { selection = value }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 11).background(selection == value ? Color.accentColor : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(selection == value ? .white : .primary).buttonStyle(.plain) } } }
}

private struct StatTile: View {
    let icon: String; let value: String; let title: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Image(systemName: icon).foregroundStyle(.blue); Text(value).font(.title2.bold()); Text(title).font(.footnote).foregroundStyle(.secondary) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)) }
}

private struct AccountView: View {
    @ObservedObject var auth: AuthStore; @ObservedObject var language: LanguageStore
    var body: some View { NavigationStack { Form { Section(language.text("Storage plan", "Forfait de stockage")) { HStack { Text(language.text("Current plan", "Forfait actuel")); Spacer(); Text("2 GB Free") } }; Section(language.text("Language", "Langue")) { Picker(language.text("Language", "Langue"), selection: $language.language) { ForEach(LanguageStore.Language.allCases) { Text($0.title).tag($0) } } }; Section { Button(language.text("Sign out", "Se déconnecter"), role: .destructive) { Task { await auth.signOut() } } } }.navigationTitle(language.text("Account", "Compte")) } }
}

private extension View { func premiumCard() -> some View { padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28)).shadow(color: .black.opacity(0.045), radius: 18, y: 7) } }

#Preview { ContentView() }
