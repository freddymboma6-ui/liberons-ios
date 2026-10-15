import SwiftUI
import Photos
import Supabase

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
        NavigationStack { VStack(spacing: 22) {
            HStack { Spacer(); Menu(language.language.title) { ForEach(LanguageStore.Language.allCases) { item in Button(item.title) { language.language = item } } }.buttonStyle(.bordered) }
            Spacer(); Text("Libérons").font(.system(size: 44, weight: .bold, design: .rounded))
            Text(language.text("Keep your memories. Free your space.", "Gardez vos souvenirs. Libérez votre espace.")).foregroundStyle(.secondary).multilineTextAlignment(.center)
            TextField(language.text("Email", "E-mail"), text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).padding().background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            SecureField(language.text("Password", "Mot de passe"), text: $password).padding().background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            if let error = auth.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
            Button { signingIn = true; Task { await auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password); signingIn = false } } label: { Group { if signingIn { ProgressView().tint(.white) } else { Text(language.text("Sign in", "Se connecter")).fontWeight(.semibold) } }.frame(maxWidth: .infinity).frame(height: 54) }.buttonStyle(.borderedProminent).disabled(signingIn || email.isEmpty || password.isEmpty)
            Spacer()
        }.padding(24) }
    }
}

private struct MainAppView: View {
    @ObservedObject var auth: AuthStore; @ObservedObject var language: LanguageStore
    @StateObject private var analyzer = PhotoLibraryAnalyzer(); @StateObject private var preferences = BackupPreferences()
    var body: some View { TabView {
        DashboardView(analyzer: analyzer, language: language).tabItem { Label(language.text("Home", "Accueil"), systemImage: "house.fill") }
        BackupView(analyzer: analyzer, preferences: preferences, language: language).tabItem { Label(language.text("Backup", "Sauvegarde"), systemImage: "icloud.and.arrow.up") }
        CloudLibraryView(language: language).tabItem { Label(language.text("Library", "Bibliothèque"), systemImage: "photo.on.rectangle.angled") }
        AccountView(auth: auth, language: language).tabItem { Label(language.text("Account", "Compte"), systemImage: "person.crop.circle") }
    }.task { await analyzer.refreshIfNeeded() } }
}

private struct DashboardView: View {
    @ObservedObject var analyzer: PhotoLibraryAnalyzer; @ObservedObject var language: LanguageStore
    var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 22) {
        Text(language.text("Your iPhone storage", "Stockage de votre iPhone")).font(.largeTitle.bold())
        if analyzer.canReadLibrary { VStack(alignment: .leading, spacing: 18) { Text(analyzer.formattedSize).font(.system(size: 45, weight: .bold, design: .rounded)); Text(language.text("estimated original library size", "taille estimée des originaux")).foregroundStyle(.secondary); HStack { MiniStat(icon: "photo", value: analyzer.photoCount.formatted(), title: "Photos"); MiniStat(icon: "video", value: analyzer.videoCount.formatted(), title: language.text("Videos", "Vidéos")) }; Button(language.text("Refresh analysis", "Actualiser l'analyse")) { Task { await analyzer.scanNow() } }.buttonStyle(.bordered).disabled(analyzer.isScanning) }.card() } else { Button(language.text("Allow Photo Access", "Autoriser l'accès aux photos")) { Task { await analyzer.requestAccessAndScan() } }.buttonStyle(.borderedProminent) }
        VStack(alignment: .leading, spacing: 10) { Label(language.text("Protected by design", "Protégé par conception"), systemImage: "checkmark.shield.fill").font(.headline); Text(language.text("Only verified cloud copies can later be offered for removal from this iPhone.", "Seules les copies cloud vérifiées pourront ensuite être proposées au retrait de cet iPhone.")).foregroundStyle(.secondary) }.card()
    }.padding(20) }.navigationTitle("Libérons") } }
}

private struct BackupView: View {
    @ObservedObject var analyzer: PhotoLibraryAnalyzer; @ObservedObject var preferences: BackupPreferences; @ObservedObject var language: LanguageStore
    @State private var testing = false; @State private var testMessage: String?; @State private var showRemovalExplanation = false
    var totalItems: Int { analyzer.photoCount + analyzer.videoCount }
    var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 20) {
        Text(language.text("Backup & Free Space", "Sauvegarde et espace")).font(.largeTitle.bold())
        VStack(alignment: .leading, spacing: 18) { Label(language.text("Choose how much to protect", "Choisissez combien protéger"), systemImage: "icloud.and.arrow.up.fill").font(.title2.bold()); PercentagePicker(selection: $preferences.backupPercent, choices: BackupPreferences.choices); Text(language.text("About \(preferences.selectedCount(total: totalItems).formatted()) of \(totalItems.formatted()) items selected.", "Environ \(preferences.selectedCount(total: totalItems).formatted()) éléments sur \(totalItems.formatted()) sélectionnés.")).font(.footnote).foregroundStyle(.secondary) }.card()
        VStack(alignment: .leading, spacing: 18) { Label(language.text("Free space on this iPhone", "Libérer de l'espace sur cet iPhone"), systemImage: "iphone.and.arrow.forward").font(.title2.bold()); PercentagePicker(selection: $preferences.removalPercent, choices: BackupPreferences.choices); HStack { Text("\(preferences.removalPercent)%").font(.system(size: 38, weight: .bold, design: .rounded)); Spacer(); Button { showRemovalExplanation = true } label: { Image(systemName: "info.circle") } }; Text(language.text("Nothing is removed automatically. Only protected originals are eligible.", "Rien n'est supprimé automatiquement. Seuls les originaux protégés sont éligibles.")).font(.footnote).foregroundStyle(.secondary) }.card()
        VStack(alignment: .leading, spacing: 14) {
            status(language.text("Uploading", "Téléversement"), "arrow.up.circle"); status(language.text("Verifying", "Vérification"), "checkmark.shield"); status(language.text("Protected", "Protégé"), "lock.shield")
            Button { testing = true; testMessage = nil; Task { await testConnection(); testing = false } } label: { HStack { Spacer(); if testing { ProgressView().tint(.white) }; Text(testing ? language.text("Testing…", "Test en cours…") : language.text("Start secure backup", "Démarrer la sauvegarde sécurisée")); Spacer() } }.buttonStyle(.borderedProminent).controlSize(.large).disabled(testing || !analyzer.canReadLibrary)
            if let testMessage { Text(testMessage).font(.footnote).foregroundStyle(.secondary) }
            Text(language.text("For safety, the first run validates the authenticated Libérons cloud path before bulk backup begins.", "Par sécurité, le premier lancement valide le chemin cloud Libérons authentifié avant la sauvegarde en masse.")).font(.caption).foregroundStyle(.secondary)
        }.card()
    }.padding(20) } }.alert(language.text("Removing from iPhone", "Retrait de l'iPhone"), isPresented: $showRemovalExplanation) { Button("OK", role: .cancel) {} } message: { Text(language.text("The protected Libérons Cloud copy remains available after local removal.", "La copie protégée Libérons Cloud reste disponible après le retrait local.")) } }

    @MainActor private func testConnection() async {
        do {
            _ = try await SupabaseService.client.auth.session
            let count = PHAsset.fetchAssets(with: nil).count
            guard count > 0 else { testMessage = language.text("No media found.", "Aucun média trouvé."); return }
            testMessage = language.text("Cloud account authenticated. \(count.formatted()) local items are ready for the protected upload pipeline.", "Compte cloud authentifié. \(count.formatted()) éléments locaux sont prêts pour le pipeline d'envoi protégé.")
        } catch { testMessage = error.localizedDescription }
    }
    private func status(_ title: String, _ icon: String) -> some View { HStack { Image(systemName: icon); Text(title); Spacer(); Circle().fill(.secondary.opacity(0.25)).frame(width: 9, height: 9) } }
}

private struct PercentagePicker: View { @Binding var selection: Int; let choices: [Int]; var body: some View { HStack(spacing: 8) { ForEach(choices, id: \.self) { value in Button("\(value)%") { selection = value }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10).background(selection == value ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(selection == value ? Color.white : Color.primary).buttonStyle(.plain) } } } }
private struct CloudLibraryView: View { @ObservedObject var language: LanguageStore; var body: some View { NavigationStack { ContentUnavailableView(language.text("Your cloud library", "Votre bibliothèque cloud"), systemImage: "photo.stack", description: Text(language.text("Protected memories will appear here.", "Vos souvenirs protégés apparaîtront ici."))).navigationTitle(language.text("Library", "Bibliothèque")) } } }
private struct AccountView: View { @ObservedObject var auth: AuthStore; @ObservedObject var language: LanguageStore; var body: some View { NavigationStack { Form { Section(language.text("Storage plan", "Forfait de stockage")) { HStack { Text(language.text("Current plan", "Forfait actuel")); Spacer(); Text("2 GB Free") } }; Section(language.text("Language", "Langue")) { Picker(language.text("Language", "Langue"), selection: $language.language) { ForEach(LanguageStore.Language.allCases) { Text($0.title).tag($0) } } }; Section { Button(language.text("Sign out", "Se déconnecter"), role: .destructive) { Task { await auth.signOut() } } } }.navigationTitle(language.text("Account", "Compte")) } } }
private struct MiniStat: View { let icon: String; let value: String; let title: String; var body: some View { VStack(alignment: .leading, spacing: 7) { Image(systemName: icon); Text(value).font(.title2.bold()); Text(title).font(.footnote).foregroundStyle(.secondary) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 18)) } }
private extension View { func card() -> some View { padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 24)) } }
#Preview { ContentView() }
