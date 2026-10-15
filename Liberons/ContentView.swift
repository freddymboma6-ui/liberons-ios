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
                TextField(language.text("Email", "E-mail"), text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).textContentType(.emailAddress).padding().background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                SecureField(language.text("Password", "Mot de passe"), text: $password).textContentType(.password).padding().background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                if let error = auth.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                Button { signingIn = true; Task { await auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password); signingIn = false } } label: {
                    Group { if signingIn { ProgressView().tint(.white) } else { Text(language.text("Sign in", "Se connecter")).fontWeight(.semibold) } }.frame(maxWidth: .infinity).frame(height: 54)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16)).disabled(signingIn || email.isEmpty || password.isEmpty)
                Text(language.text("Use your existing Libérons account.", "Utilisez votre compte Libérons existant.")).font(.footnote).foregroundStyle(.secondary)
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
    var body: some View {
        TabView {
            DashboardView(analyzer: analyzer, language: language).tabItem { Label(language.text("Home", "Accueil"), systemImage: "house.fill") }
            BackupView(analyzer: analyzer, preferences: preferences, language: language).tabItem { Label(language.text("Backup", "Sauvegarde"), systemImage: "icloud.and.arrow.up") }
            CloudLibraryView(language: language).tabItem { Label(language.text("Library", "Bibliothèque"), systemImage: "photo.on.rectangle.angled") }
            AccountView(auth: auth, language: language).tabItem { Label(language.text("Account", "Compte"), systemImage: "person.crop.circle") }
        }.task { await analyzer.refreshIfNeeded() }
    }
}

private struct DashboardView: View {
    @ObservedObject var analyzer: PhotoLibraryAnalyzer
    @ObservedObject var language: LanguageStore
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) { Text(language.text("Your iPhone storage", "Stockage de votre iPhone")).font(.largeTitle.bold()); Text(language.text("Understand your library before backing anything up.", "Comprenez votre photothèque avant toute sauvegarde.")).foregroundStyle(.secondary) }
            if analyzer.canReadLibrary { analysisCard } else { permissionCard }
            if analyzer.canReadLibrary && analyzer.hasCompletedScan { recommendationCard }
            VStack(alignment: .leading, spacing: 10) { Label(language.text("Protected by design", "Protégé par conception"), systemImage: "checkmark.shield.fill").font(.headline); Text(language.text("Libérons only offers removal after the cloud copy is uploaded and verified.", "Libérons ne propose le retrait qu'après téléversement et vérification de la copie cloud.")).foregroundStyle(.secondary) }.card()
        }.padding(20) }.navigationTitle("Libérons").navigationBarTitleDisplayMode(.inline) }
    }
    private var permissionCard: some View { VStack(alignment: .leading, spacing: 16) { Image(systemName: "photo.stack").font(.system(size: 42)); Text(language.text("Analyze your photo library", "Analyser votre photothèque")).font(.title2.bold()); Text(language.text("Nothing is uploaded during this analysis.", "Aucun fichier n'est téléversé pendant cette analyse.")).foregroundStyle(.secondary); Button(language.text("Allow Photo Access", "Autoriser l'accès aux photos")) { Task { await analyzer.requestAccessAndScan() } }.buttonStyle(.borderedProminent).controlSize(.large) }.card() }
    private var analysisCard: some View { VStack(alignment: .leading, spacing: 18) {
        if analyzer.isScanning && !analyzer.hasCompletedScan { Text(language.text("Analyzing your library…", "Analyse de votre photothèque…")).font(.headline); ProgressView(value: Double(analyzer.scannedItems), total: Double(max(analyzer.totalItems, 1))); Text("\(analyzer.scannedItems.formatted()) / \(analyzer.totalItems.formatted())").font(.caption).foregroundStyle(.secondary) }
        else if analyzer.isScanning { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(language.text("Updating in the background…", "Mise à jour en arrière-plan…")) }.font(.caption).foregroundStyle(.secondary) }
        Text(analyzer.formattedSize).font(.system(size: 45, weight: .bold, design: .rounded)); Text(language.text("estimated original library size", "taille estimée des originaux")).foregroundStyle(.secondary)
        HStack(spacing: 12) { MiniStat(icon: "photo", value: analyzer.photoCount.formatted(), title: "Photos"); MiniStat(icon: "video", value: analyzer.videoCount.formatted(), title: language.text("Videos", "Vidéos")) }
        if let date = analyzer.formattedLastScan { Label(language.text("Last analyzed: \(date)", "Dernière analyse : \(date)"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary) }
        Button(language.text("Refresh analysis", "Actualiser l'analyse")) { Task { await analyzer.scanNow() } }.buttonStyle(.bordered).disabled(analyzer.isScanning)
    }.card() }
    private var recommendationCard: some View { let plan = recommendedPlan(bytes: analyzer.estimatedBytes); return VStack(alignment: .leading, spacing: 12) { Label(language.text("Recommended for you", "Recommandé pour vous"), systemImage: "sparkles").font(.headline); HStack { Text(plan.name).font(.system(size: 34, weight: .bold, design: .rounded)); Spacer(); Text(plan.price).font(.title3.bold()) }; Text(language.text("Enough room for your current library with space to keep growing.", "Assez d'espace pour votre photothèque actuelle et vos prochains souvenirs.")).foregroundStyle(.secondary) }.padding(20).background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 24)) }
    private func recommendedPlan(bytes: Int64) -> (name: String, price: String) { let gb = Double(bytes) / 1_000_000_000; if gb <= 33 { return ("50 GB", "$4.99/mo") }; if gb <= 66 { return ("100 GB", "$7.99/mo") }; if gb <= 166 { return ("250 GB", "$12.99/mo") }; if gb <= 333 { return ("500 GB", "$17.99/mo") }; return ("1 TB", "$24.99/mo") }
}

private struct BackupView: View {
    @ObservedObject var analyzer: PhotoLibraryAnalyzer
    @ObservedObject var preferences: BackupPreferences
    @ObservedObject var language: LanguageStore
    @State private var showRemovalExplanation = false
    var totalItems: Int { analyzer.photoCount + analyzer.videoCount }
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text(language.text("Backup & Free Space", "Sauvegarde et espace")).font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 18) {
                Label(language.text("Choose how much to protect", "Choisissez combien protéger"), systemImage: "icloud.and.arrow.up.fill").font(.title2.bold())
                Text(language.text("Backup selection", "Sélection à sauvegarder")).font(.headline)
                PercentagePicker(selection: $preferences.backupPercent, choices: BackupPreferences.choices)
                Text(language.text("About \(preferences.selectedCount(total: totalItems).formatted()) of \(totalItems.formatted()) items will be selected for cloud protection.", "Environ \(preferences.selectedCount(total: totalItems).formatted()) éléments sur \(totalItems.formatted()) seront sélectionnés pour la protection cloud.")).font(.footnote).foregroundStyle(.secondary)
            }.card()

            VStack(alignment: .leading, spacing: 18) {
                Label(language.text("Free space on this iPhone", "Libérer de l'espace sur cet iPhone"), systemImage: "iphone.and.arrow.forward").font(.title2.bold())
                Text(language.text("After backup and verification, choose what percentage of protected originals Libérons may propose to remove from Apple Photos.", "Après sauvegarde et vérification, choisissez quel pourcentage des originaux protégés Libérons pourra proposer de retirer d'Apple Photos.")).foregroundStyle(.secondary)
                PercentagePicker(selection: $preferences.removalPercent, choices: BackupPreferences.choices)
                HStack { Text("\(preferences.removalPercent)%").font(.system(size: 38, weight: .bold, design: .rounded)); Spacer(); Button { showRemovalExplanation = true } label: { Image(systemName: "info.circle") } }
                Text(language.text("Nothing is removed automatically. Only verified, protected items are eligible, and iOS will ask you to confirm the deletion.", "Rien n'est supprimé automatiquement. Seuls les éléments vérifiés et protégés sont éligibles, et iOS vous demandera de confirmer la suppression.")).font(.footnote).foregroundStyle(.secondary)
            }.card()

            VStack(alignment: .leading, spacing: 14) {
                status(language.text("Uploading", "Téléversement"), "arrow.up.circle"); status(language.text("Uploaded", "Téléversé"), "checkmark.circle"); status(language.text("Verifying", "Vérification"), "checkmark.shield"); status(language.text("Protected", "Protégé"), "lock.shield")
                Button(language.text("Start secure backup", "Démarrer la sauvegarde sécurisée")) { }.buttonStyle(.borderedProminent).controlSize(.large).disabled(true)
                Text(language.text("The controls are ready. The upload worker will activate this button after the first end-to-end B2 test.", "Les contrôles sont prêts. Le moteur d'envoi activera ce bouton après le premier test B2 de bout en bout.")).font(.caption).foregroundStyle(.secondary)
            }.card()
        }.padding(20) } }
        .alert(language.text("Removing from iPhone", "Retrait de l'iPhone"), isPresented: $showRemovalExplanation) { Button("OK", role: .cancel) {} } message: { Text(language.text("Removing from iPhone is different from deleting from Libérons Cloud. Your protected cloud copy stays available for viewing or restoration.", "Retirer de l'iPhone est différent de supprimer de Libérons Cloud. Votre copie cloud protégée reste disponible pour consultation ou restauration.")) }
    }
    private func status(_ title: String, _ icon: String) -> some View { HStack { Image(systemName: icon); Text(title); Spacer(); Circle().fill(.secondary.opacity(0.25)).frame(width: 9, height: 9) } }
}

private struct PercentagePicker: View {
    @Binding var selection: Int
    let choices: [Int]
    var body: some View { HStack(spacing: 8) { ForEach(choices, id: \.self) { value in Button("\(value)%") { selection = value }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10).background(selection == value ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(selection == value ? Color.white : Color.primary).buttonStyle(.plain) } } }
}

private struct CloudLibraryView: View { @ObservedObject var language: LanguageStore; var body: some View { NavigationStack { ContentUnavailableView(language.text("Your cloud library", "Votre bibliothèque cloud"), systemImage: "photo.stack", description: Text(language.text("Protected memories will appear here without filling your iPhone again.", "Vos souvenirs protégés apparaîtront ici sans remplir à nouveau votre iPhone."))).navigationTitle(language.text("Library", "Bibliothèque")) } } }

private struct AccountView: View {
    @ObservedObject var auth: AuthStore; @ObservedObject var language: LanguageStore
    var body: some View { NavigationStack { Form { Section(language.text("Storage plan", "Forfait de stockage")) { HStack { Text(language.text("Current plan", "Forfait actuel")); Spacer(); Text("2 GB Free").foregroundStyle(.secondary) }; HStack { Text(language.text("Cloud used", "Cloud utilisé")); Spacer(); Text("0 GB / 2 GB").foregroundStyle(.secondary) } }; Section(language.text("Language", "Langue")) { Picker(language.text("Language", "Langue"), selection: $language.language) { ForEach(LanguageStore.Language.allCases) { item in Text(item.title).tag(item) } } }; Section(language.text("Security", "Sécurité")) { Label(language.text("Verified backups before removal", "Sauvegardes vérifiées avant suppression"), systemImage: "checkmark.shield") }; Section { Button(language.text("Sign out", "Se déconnecter"), role: .destructive) { Task { await auth.signOut() } } } }.navigationTitle(language.text("Account", "Compte")) } }
}

private struct MiniStat: View { let icon: String; let value: String; let title: String; var body: some View { VStack(alignment: .leading, spacing: 7) { Image(systemName: icon).foregroundStyle(.secondary); Text(value).font(.title2.bold()); Text(title).font(.footnote).foregroundStyle(.secondary) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 18)) } }
private extension View { func card() -> some View { padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 24)) } }
#Preview { ContentView() }
