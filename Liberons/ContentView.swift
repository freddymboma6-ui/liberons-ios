import SwiftUI
import Photos
import Auth

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
                Button { signingIn = true; Task { await auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password); signingIn = false } } label: { Group { if signingIn { ProgressView().tint(.white) } else { Text(language.text("Sign in", "Se connecter")).fontWeight(.semibold) } }.frame(maxWidth: .infinity).frame(height: 54) }.buttonStyle(.borderedProminent).disabled(signingIn || email.isEmpty || password.isEmpty)
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
            AccountView(auth: auth, cloud: cloud, language: language).tabItem { Label(language.text("Account", "Compte"), systemImage: "person.crop.circle.fill") }
        }.task { async let a: Void = analyzer.refreshIfNeeded(); async let b: Void = cloud.refresh(); _ = await (a, b) }
    }
}

private struct DashboardView: View {
    @ObservedObject var analyzer: PhotoLibraryAnalyzer
    @ObservedObject var cloud: CloudStorageSummary
    @ObservedObject var language: LanguageStore
    private var total: Int { analyzer.photoCount + analyzer.videoCount }
    private var percent: Int { total == 0 ? 0 : min(100, Int(Double(cloud.protectedCount) / Double(total) * 100)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Libérons").font(.system(size: 38, weight: .bold, design: .rounded))
                    Text(language.text("Your memories, without the storage stress.", "Vos souvenirs, sans le stress du stockage.")).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 16) {
                        Label(language.text("Your photo library", "Votre photothèque"), systemImage: "photo.stack.fill").font(.headline)
                        Text(analyzer.formattedSize).font(.system(size: 48, weight: .bold, design: .rounded))
                        Text(language.text("across \(total.formatted()) photos and videos", "répartis sur \(total.formatted()) photos et vidéos")).foregroundStyle(.secondary)
                        HStack(spacing: 10) { Metric(icon: "photo.fill", value: analyzer.photoCount.formatted(), label: "Photos", tint: .blue); Metric(icon: "video.fill", value: analyzer.videoCount.formatted(), label: language.text("Videos", "Vidéos"), tint: .purple) }
                    }.card()
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Label("Libérons Cloud", systemImage: "icloud.fill").font(.headline).foregroundStyle(.blue); Spacer(); Text(bytes(cloud.protectedBytes)).fontWeight(.bold) }
                        ProgressView(value: cloud.quotaBytes > 0 ? min(1, Double(cloud.protectedBytes + cloud.pendingBytes) / Double(cloud.quotaBytes)) : 0).tint(.blue)
                        HStack(spacing: 10) { Metric(icon: "checkmark.shield.fill", value: cloud.protectedCount.formatted(), label: language.text("Protected", "Protégés"), tint: .green); Metric(icon: "externaldrive.fill", value: cloud.quotaBytes > 0 ? bytes(cloud.quotaBytes) : "—", label: language.text("Cloud plan", "Forfait cloud"), tint: .blue) }
                    }.card()
                    HStack(spacing: 10) { Metric(icon: "shield.checkered", value: "\(percent)%", label: language.text("Library protected", "Photothèque protégée"), tint: .green); Metric(icon: "photo.on.rectangle.angled", value: max(0, total - cloud.protectedCount).formatted(), label: language.text("Still local", "Encore locaux"), tint: .orange) }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(language.text("Protection status", "État de protection")).font(.headline)
                        Label(cloud.protectedCount > 0 ? language.text("Cloud protection active", "Protection cloud active") : language.text("Ready to protect", "Prêt à protéger"), systemImage: cloud.protectedCount > 0 ? "checkmark.circle.fill" : "shield.fill").foregroundStyle(cloud.protectedCount > 0 ? .green : .orange)
                        Divider()
                        Label(language.text("Originals stay on this iPhone until you choose to free space.", "Les originaux restent sur cet iPhone jusqu’à ce que vous choisissiez de libérer de l’espace."), systemImage: "iphone").font(.subheadline).foregroundStyle(.secondary)
                    }.card()
                    Button { Task { async let a: Void = analyzer.scanNow(); async let b: Void = cloud.refresh(); _ = await (a, b) } } label: { Label(language.text("Refresh dashboard", "Actualiser le tableau de bord"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity).frame(height: 42) }.buttonStyle(.borderedProminent).disabled(analyzer.isScanning || cloud.isLoading)
                }.padding(20).padding(.bottom, 100)
            }.background(Color(uiColor: .systemGroupedBackground)).toolbar(.hidden, for: .navigationBar)
        }
    }
    private func bytes(_ n: Int64) -> String { n == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}

private struct BackupView: View {
    @ObservedObject var analyzer: PhotoLibraryAnalyzer
    @ObservedObject var preferences: BackupPreferences
    @ObservedObject var backup: BackupEngine
    @ObservedObject var language: LanguageStore
    private var total: Int { analyzer.photoCount + analyzer.videoCount }
    private var protectedBytes: Int64 { Int64(Double(analyzer.estimatedBytes) * Double(preferences.backupPercent) / 100) }
    private var removableBytes: Int64 { Int64(Double(protectedBytes) * Double(preferences.removalPercent) / 100) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(language.text("Free your space", "Libérez votre espace")).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(language.text("Protect first. Remove locally only after verification.", "Protégez d'abord. Retirez localement uniquement après vérification.")).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 16) {
                        Label(language.text("1. Protect in Libérons Cloud", "1. Protéger dans Libérons Cloud"), systemImage: "icloud.and.arrow.up.fill").font(.headline).foregroundStyle(.blue)
                        Text(ByteCountFormatter.string(fromByteCount: protectedBytes, countStyle: .file)).font(.system(size: 40, weight: .bold, design: .rounded))
                        Text(language.text("about \(preferences.selectedCount(total: total).formatted()) items", "environ \(preferences.selectedCount(total: total).formatted()) éléments")).foregroundStyle(.secondary)
                        PercentPicker(selection: $preferences.backupPercent)
                    }.card()
                    BackupQueueView(backup: backup, preferences: preferences, analyzer: analyzer, language: language)
                    VStack(alignment: .leading, spacing: 16) {
                        Label(language.text("2. Free space on this iPhone", "2. Libérer de l'espace sur cet iPhone"), systemImage: "iphone.and.arrow.forward").font(.headline).foregroundStyle(.green)
                        Text(ByteCountFormatter.string(fromByteCount: removableBytes, countStyle: .file)).font(.system(size: 40, weight: .bold, design: .rounded))
                        PercentPicker(selection: $preferences.removalPercent)
                        Text(language.text("Only verified protected originals are eligible.", "Seuls les originaux protégés et vérifiés sont éligibles.")).font(.caption).foregroundStyle(.secondary)
                    }.card()
                    FreeSpaceView(preferences: preferences, language: language)
                }.padding(20).padding(.bottom, 100)
            }.toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct AccountView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var cloud: CloudStorageSummary
    @ObservedObject var language: LanguageStore
    @State private var showingLanguagePicker = false
    private var email: String { auth.session?.user.email ?? "Libérons" }
    private var initials: String { String(email.prefix(1)).uppercased() }
    private var used: Int64 { cloud.protectedBytes + cloud.pendingBytes }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(language.text("Account", "Compte")).font(.system(size: 38, weight: .bold, design: .rounded))
                    HStack(spacing: 14) { ZStack { Circle().fill(Color.blue.gradient).frame(width: 58, height: 58); Text(initials).font(.title2.bold()).foregroundStyle(.white) }; VStack(alignment: .leading) { Text(email).font(.headline).lineLimit(1); Text(language.text("Libérons account", "Compte Libérons")).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue) }.card()
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Label(language.text("Cloud storage", "Stockage cloud"), systemImage: "icloud.fill").font(.headline).foregroundStyle(.blue); Spacer(); Text(cloud.quotaBytes > 0 ? ByteCountFormatter.string(fromByteCount: cloud.quotaBytes, countStyle: .file) : language.text("Free", "Gratuit")).fontWeight(.bold) }
                        ProgressView(value: cloud.quotaBytes > 0 ? min(1, Double(used) / Double(cloud.quotaBytes)) : 0).tint(.blue)
                        HStack { Text(language.text("Used", "Utilisé")); Spacer(); Text(used == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: used, countStyle: .file)).fontWeight(.semibold) }
                        NavigationLink { StoragePlanView(cloud: cloud, language: language) } label: { HStack { Text(language.text("Manage storage plan", "Gérer le forfait de stockage")); Spacer(); Image(systemName: "chevron.right") } }.foregroundStyle(.blue)
                    }.card()
                    VStack(spacing: 0) {
                        Button { showingLanguagePicker = true } label: { SettingRow(icon: "globe", title: language.text("Language", "Langue"), trailing: language.language.title) }.buttonStyle(.plain)
                        Divider()
                        SettingRow(icon: "bell.fill", title: language.text("Notifications", "Notifications"))
                        Divider()
                        SettingRow(icon: "lock.shield.fill", title: language.text("Privacy & security", "Confidentialité et sécurité"))
                    }.card()
                    VStack(spacing: 0) { SettingRow(icon: "questionmark.circle.fill", title: language.text("Help & support", "Aide et support")); Divider(); SettingRow(icon: "info.circle.fill", title: language.text("About Libérons", "À propos de Libérons")) }.card()
                    Button(role: .destructive) { Task { await auth.signOut() } } label: { Label(language.text("Sign out", "Se déconnecter"), systemImage: "rectangle.portrait.and.arrow.right").fontWeight(.semibold).frame(maxWidth: .infinity).frame(height: 48) }.buttonStyle(.bordered).tint(.red)
                }.padding(20).padding(.bottom, 100)
            }.background(Color(uiColor: .systemGroupedBackground)).toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog(language.text("Choose language", "Choisir la langue"), isPresented: $showingLanguagePicker, titleVisibility: .visible) {
            ForEach(LanguageStore.Language.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { language.language = item }
                } label: {
                    if item == language.language { Label(item.title, systemImage: "checkmark") }
                    else { Text(item.title) }
                }
            }
            Button(language.text("Cancel", "Annuler"), role: .cancel) {}
        }
    }
}

private struct StoragePlanView: View {
    @ObservedObject var cloud: CloudStorageSummary
    @ObservedObject var language: LanguageStore
    private var used: Int64 { cloud.protectedBytes + cloud.pendingBytes }
    private var available: Int64 { max(0, cloud.quotaBytes - used) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Image(systemName: "icloud.fill").font(.title).foregroundStyle(.blue); VStack(alignment: .leading) { Text(language.text("Current plan", "Forfait actuel")).font(.caption).foregroundStyle(.secondary); Text(cloud.quotaBytes > 0 ? ByteCountFormatter.string(fromByteCount: cloud.quotaBytes, countStyle: .file) : language.text("Free", "Gratuit")).font(.title2.bold()) }; Spacer() }
                    ProgressView(value: cloud.quotaBytes > 0 ? min(1, Double(used) / Double(cloud.quotaBytes)) : 0).tint(.blue)
                    HStack { VStack(alignment: .leading) { Text(language.text("Used", "Utilisé")).font(.caption).foregroundStyle(.secondary); Text(used == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: used, countStyle: .file)).fontWeight(.semibold) }; Spacer(); if cloud.quotaBytes > 0 { VStack(alignment: .trailing) { Text(language.text("Available", "Disponible")).font(.caption).foregroundStyle(.secondary); Text(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)).fontWeight(.semibold) } } }
                }.card()
                VStack(alignment: .leading, spacing: 12) { Label(language.text("Your cloud protection", "Votre protection cloud"), systemImage: "checkmark.shield.fill").font(.headline).foregroundStyle(.green); HStack { Text(language.text("Protected memories", "Souvenirs protégés")); Spacer(); Text(cloud.protectedCount.formatted()).fontWeight(.semibold) }; if cloud.pendingBytes > 0 { Divider(); HStack { Text(language.text("Being protected", "En cours de protection")); Spacer(); Text(ByteCountFormatter.string(fromByteCount: cloud.pendingBytes, countStyle: .file)).fontWeight(.semibold) } } }.card()
                VStack(alignment: .leading, spacing: 10) { Label(language.text("Plan management", "Gestion du forfait"), systemImage: "person.crop.circle.badge.checkmark").font(.headline); Text(language.text("The app reflects the storage plan linked to your Libérons account. Purchases and billing are not performed inside this app.", "L’app affiche le forfait de stockage lié à votre compte Libérons. Les achats et la facturation ne sont pas effectués dans cette application.")).font(.subheadline).foregroundStyle(.secondary) }.card()
                Button { Task { await cloud.refresh() } } label: { Label(language.text("Refresh plan status", "Actualiser l’état du forfait"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity).frame(height: 42) }.buttonStyle(.borderedProminent).disabled(cloud.isLoading)
            }.padding(20)
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(language.text("Storage plan", "Forfait de stockage")).navigationBarTitleDisplayMode(.inline)
    }
}

private struct PercentPicker: View {
    @Binding var selection: Int
    var body: some View { HStack(spacing: 7) { ForEach(BackupPreferences.choices, id: \.self) { value in Button("\(value)%") { selection = value }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10).background(selection == value ? Color.accentColor : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(selection == value ? .white : .primary).buttonStyle(.plain) } } }
}

private struct Metric: View {
    let icon: String; let value: String; let label: String; let tint: Color
    var body: some View { VStack(alignment: .leading, spacing: 7) { Image(systemName: icon).foregroundStyle(tint); Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7); Text(label).font(.caption).foregroundStyle(.secondary) }.padding(15).frame(maxWidth: .infinity, minHeight: 100, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)) }
}

private struct SettingRow: View {
    let icon: String; let title: String; var trailing: String = ""
    var body: some View { HStack(spacing: 13) { Image(systemName: icon).foregroundStyle(.blue).frame(width: 25); Text(title); Spacer(); if !trailing.isEmpty { Text(trailing).foregroundStyle(.secondary) }; Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }.padding(.vertical, 13).contentShape(Rectangle()) }
}

private extension View {
    func card() -> some View { padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28)).shadow(color: .black.opacity(0.045), radius: 18, y: 7) }
}

#Preview { ContentView() }
