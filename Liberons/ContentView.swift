import SwiftUI
import Photos
import Auth
import Supabase

struct ContentView: View {
    @ObservedObject var auth: AuthStore
    @StateObject private var language = LanguageStore()
    var body: some View { Group { if auth.isLoading { ProgressView() } else if auth.isAuthenticated { MainAppView(auth: auth, language: language) } else { SignInView(auth: auth, language: language) } } }
}

private struct SignInView: View {
    @ObservedObject var auth: AuthStore; @ObservedObject var language: LanguageStore
    @State private var email=""; @State private var password=""; @State private var signingIn=false; @State private var resendingConfirmation=false
    private func authError(_ key:String)->String{switch key{case "auth_invalid_credentials":return language.text("Incorrect email or password.","E-mail ou mot de passe incorrect.");case "auth_email_not_confirmed":return language.text("Your email address has not been verified. Open the confirmation email from Libérons and tap its verification link, then return here to sign in. Check your spam folder if you cannot find it.","Votre adresse e-mail n’est pas encore vérifiée. Ouvrez le courriel de confirmation envoyé par Libérons, appuyez sur le lien de vérification, puis revenez ici pour vous connecter. Vérifiez vos courriels indésirables si vous ne le trouvez pas.");case "auth_user_already_registered":return language.text("An account already exists with this email.","Un compte existe déjà avec cet e-mail.");case "auth_password_too_short":return language.text("Your password must contain at least 8 characters.","Votre mot de passe doit contenir au moins 8 caractères.");case "auth_invalid_email":return language.text("Enter a valid email address.","Saisissez une adresse e-mail valide.");case "auth_network_error":return language.text("Unable to connect. Check your internet connection and try again.","Connexion impossible. Vérifiez votre connexion Internet et réessayez.");case "auth_too_many_requests":return language.text("Too many attempts. Please wait a moment and try again.","Trop de tentatives. Patientez un instant puis réessayez.");default:return language.text("Something went wrong. Please try again.","Une erreur est survenue. Veuillez réessayer.")}}
    var body: some View { NavigationStack { VStack(spacing:22) { HStack{Spacer();Menu(language.language.title){ForEach(LanguageStore.Language.allCases){item in Button(item.title){language.language=item}}}.buttonStyle(.bordered)};Spacer();Text("Libérons").font(.system(size:44,weight:.bold,design:.rounded));Text(language.text("Keep your memories. Free your space.","Gardez vos souvenirs. Libérez votre espace.")).foregroundStyle(.secondary).multilineTextAlignment(.center);TextField(language.text("Email","E-mail"),text:$email).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textContentType(.emailAddress).padding().background(.secondary.opacity(0.10),in:RoundedRectangle(cornerRadius:16));SecureField(language.text("Password","Mot de passe"),text:$password).textContentType(.password).padding().background(.secondary.opacity(0.10),in:RoundedRectangle(cornerRadius:16));HStack{Spacer();NavigationLink{ForgotPasswordView(auth:auth,language:language,email:email)}label:{Text(language.text("Forgot password?","Mot de passe oublié ?")).font(.subheadline.weight(.semibold)).foregroundStyle(.blue)}};if let error=auth.errorMessage{Text(authError(error)).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)};if auth.pendingConfirmationEmail != nil && (auth.infoMessage == "confirmation_required" || auth.infoMessage == "confirmation_resent") {
    VStack(spacing:12) {
        Image(systemName:"envelope.badge.shield.half.filled").font(.system(size:34)).foregroundStyle(.blue)
        Text(language.text("Verify your email address","Vérifiez votre adresse e-mail")).font(.headline)
        if let pendingEmail=auth.pendingConfirmationEmail {
            Text(pendingEmail).font(.subheadline.weight(.semibold)).textSelection(.enabled)
        }
        Text(language.text("Open the email from Libérons and tap the verification link. Then return to the app to sign in. Check your spam folder if you do not see the message.","Ouvrez le courriel envoyé par Libérons et appuyez sur le lien de vérification. Revenez ensuite dans l’application pour vous connecter. Vérifiez les indésirables si vous ne voyez pas le message."))
            .font(.footnote).multilineTextAlignment(.center)
        if auth.infoMessage == "confirmation_resent" {
            Label(language.text("Another confirmation email was requested.","Un nouveau courriel de confirmation a été demandé."),systemImage:"checkmark.circle")
                .font(.footnote).foregroundStyle(.green)
        }
        Button {
            resendingConfirmation=true
            Task {
                _ = await auth.resendConfirmationEmail()
                resendingConfirmation=false
            }
        } label: {
            if resendingConfirmation {ProgressView()} else {Label(language.text("Resend verification email","Renvoyer le courriel de vérification"),systemImage:"arrow.clockwise")}
        }.disabled(resendingConfirmation)
        Button(language.text("Use another email address","Utiliser une autre adresse e-mail")) {
            auth.dismissPendingConfirmation()
        }.font(.footnote)
    }.padding(14).frame(maxWidth:.infinity).background(.blue.opacity(0.08),in:RoundedRectangle(cornerRadius:14))
};Button{signingIn=true;Task{await auth.signIn(email:email.trimmingCharacters(in:.whitespacesAndNewlines),password:password);signingIn=false}}label:{Group{if signingIn{ProgressView().tint(.white)}else{Text(language.text("Sign in","Se connecter")).fontWeight(.semibold)}}.frame(maxWidth:.infinity).frame(height:54)}.buttonStyle(.borderedProminent).disabled(signingIn||email.isEmpty||password.isEmpty);HStack(spacing:5){Text(language.text("New to Libérons?","Nouveau sur Libérons ?")).foregroundStyle(.secondary);NavigationLink{SignUpView(auth:auth,language:language)}label:{Text(language.text("Create account","Créer un compte")).fontWeight(.semibold).foregroundStyle(.blue)}}.font(.subheadline);Spacer()}.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).background(LiberonsTheme.canvas.ignoresSafeArea()) } }
}

private struct MainAppView: View {
    @ObservedObject var auth:AuthStore; @ObservedObject var language:LanguageStore
    @StateObject private var analyzer=PhotoLibraryAnalyzer(); @StateObject private var preferences=BackupPreferences(); @StateObject private var backup=BackupEngine(); @StateObject private var cloud=CloudStorageSummary(); @StateObject private var coverage=DeviceProtectionCoverage()
    var body: some View { TabView { DashboardView(analyzer:analyzer,cloud:cloud,coverage:coverage,language:language).tabItem{Label(language.text("Home","Accueil"),systemImage:"house.fill")}; BackupView(analyzer:analyzer,preferences:preferences,backup:backup,language:language).tabItem{Label(language.text("Backup","Sauvegarde"),systemImage:"icloud.and.arrow.up.fill")}; ProtectedLibraryView(language:language).tabItem{Label(language.text("Library","Bibliothèque"),systemImage:"photo.on.rectangle.angled")}; AccountView(auth:auth,cloud:cloud,language:language).tabItem{Label(language.text("Account","Compte"),systemImage:"person.crop.circle.fill")} }.task{async let a:Void=analyzer.refreshIfNeeded();async let b:Void=cloud.refresh();_=await(a,b);await coverage.refresh()} }
}

private struct DashboardView: View {
    @ObservedObject var analyzer:PhotoLibraryAnalyzer; @ObservedObject var cloud:CloudStorageSummary; @ObservedObject var coverage:DeviceProtectionCoverage; @ObservedObject var language:LanguageStore
    @State private var refreshing=false
    private var total:Int{analyzer.photoCount+analyzer.videoCount}; private var percent:Int{coverage.percent}; private var effectiveQuota:Int64{cloud.quotaBytes>0 ? cloud.quotaBytes:2_000_000_000}
    private var billedPlanDisplay:String{cloud.billedPlanQuotaBytes<=2_050_000_000 ? language.text("Free · 2 GB","Gratuit · 2 Go"):bytes(cloud.billedPlanQuotaBytes)}
    private var giftedDisplay:String{"+\(bytes(cloud.grantedBonusBytes))"}
    private var protectionStatusColor:Color{if !cloud.hasLoadedData{return Color.secondary};return cloud.protectedCount>0 ? Color.green:Color.orange}
    var body: some View { NavigationStack{ScrollView{VStack(alignment:.leading,spacing:16){Text("Libérons").font(.system(size:38,weight:.bold,design:.rounded));Text(language.text("Your memories, without the storage stress.","Vos souvenirs, sans le stress du stockage.")).foregroundStyle(.secondary);VStack(alignment:.leading,spacing:16){Label(language.text("Your photo library","Votre photothèque"),systemImage:"photo.stack.fill").font(.headline);Text(bytes(analyzer.estimatedBytes)).font(.system(size:48,weight:.bold,design:.rounded));Text(language.text("across \(total.formatted()) photos and videos","répartis sur \(total.formatted()) photos et vidéos")).foregroundStyle(.secondary);HStack(spacing:10){Metric(icon:"photo.fill",value:analyzer.photoCount.formatted(),label:"Photos",tint:.blue);Metric(icon:"video.fill",value:analyzer.videoCount.formatted(),label:language.text("Videos","Vidéos"),tint:.purple)}}.card();VStack(alignment:.leading,spacing:14){HStack{Label("Libérons",systemImage:"icloud.fill").font(.headline).foregroundStyle(.blue);Spacer();Group { if cloud.hasLoadedData { Text(bytes(cloud.protectedBytes)) } else { ProgressView().controlSize(.small) } }.fontWeight(.bold)};ProgressView(value:min(1,Double(cloud.usedBytes)/Double(effectiveQuota))).tint(.blue);HStack(spacing:10){Metric(icon:"checkmark.shield.fill",value:cloud.hasLoadedData ? cloud.protectedCount.formatted() : "—",label:language.text("Protected","Protégés"),tint:.green);Metric(icon:"creditcard.fill",value:billedPlanDisplay,label:language.text("Current plan","Forfait actuel"),tint:.blue)};if cloud.hasGrantedBonus{HStack(spacing:10){Image(systemName:"gift.fill").foregroundStyle(.green);VStack(alignment:.leading,spacing:2){Text(language.text("Offered by Libérons","Offert par Libérons")).font(.caption).foregroundStyle(.secondary);Text(giftedDisplay).font(.headline)};Spacer();VStack(alignment:.trailing,spacing:2){Text(language.text("Total capacity","Capacité totale")).font(.caption).foregroundStyle(.secondary);Text(bytes(effectiveQuota)).font(.headline)}}.padding(14).background(Color.green.opacity(0.08),in:RoundedRectangle(cornerRadius:18,style:.continuous))}}.card();HStack(alignment:.top,spacing:10){Metric(icon:"shield.checkered",value:"\(percent)%",label:language.text("Library protected","Photothèque protégée"),tint:.green).frame(maxWidth:.infinity).frame(height:174,alignment:.top);DeviceMediaMetric(value:total.formatted(),label:language.text("On this iPhone","Sur cet iPhone")).frame(maxWidth:.infinity).frame(height:174,alignment:.top)};VStack(alignment:.leading,spacing:12){Text(language.text("Protection status","État de protection")).font(.headline);Label(!cloud.hasLoadedData ? language.text("Checking protection…","Vérification de la protection…") : (cloud.protectedCount>0 ? language.text("Libérons protection is active","Protection Libérons active"):language.text("Ready to protect","Prêt à protéger")),systemImage:!cloud.hasLoadedData ? "arrow.triangle.2.circlepath" : (cloud.protectedCount>0 ? "checkmark.circle.fill":"shield.fill")).foregroundStyle(protectionStatusColor);Divider();Label(language.text("Originals stay on this iPhone until you choose to free space.","Les originaux restent sur cet iPhone jusqu’à ce que vous choisissiez de libérer de l’espace."),systemImage:"iphone").font(.subheadline).foregroundStyle(.secondary)}.card();Button{guard !refreshing else{return};refreshing=true;Task{async let a:Void=analyzer.refreshDashboardFast();async let b:Void=cloud.refresh();_=await(a,b);await coverage.refresh();refreshing=false}}label:{HStack{if refreshing{ProgressView().controlSize(.small)};Label(language.text(refreshing ? "Refreshing…":"Refresh dashboard",refreshing ? "Actualisation…":"Actualiser le tableau de bord"),systemImage:"arrow.clockwise")}.frame(maxWidth:.infinity).frame(height:42)}.buttonStyle(.borderedProminent).disabled(refreshing||cloud.isLoading)}.padding(20).padding(.bottom,100)}.background(LiberonsTheme.canvas).toolbar(.hidden,for:.navigationBar)} }
    private func bytes(_ n:Int64)->String{if n==0{return language.text("0 KB","0 Ko")};if n>=999_000_000_000{return String(format:"%.0f %@",Double(n)/1_000_000_000_000,language.text("TB","To"))};if n>=1_000_000_000{return String(format:n%1_000_000_000==0 ? "%.0f %@":"%.2f %@",Double(n)/1_000_000_000,language.text("GB","Go"))};return ByteCountFormatter.string(fromByteCount:n,countStyle:.file)}
}

private struct BackupView: View {
    private func storageSize(_ n:Int64)->String{
        if n <= 0 { return language.text("0 KB", "0 Ko") }
        if n >= 1_000_000_000_000 { return String(format:"%.2f %@", Double(n)/1_000_000_000_000, language.text("TB","To")) }
        if n >= 1_000_000_000 { return String(format:"%.2f %@", Double(n)/1_000_000_000, language.text("GB","Go")) }
        let formatted = ByteCountFormatter.string(fromByteCount:n,countStyle:.file)
        return language.language == .french ? formatted.replacingOccurrences(of:"KB",with:"Ko").replacingOccurrences(of:"MB",with:"Mo") : formatted
    }
    @ObservedObject var analyzer:PhotoLibraryAnalyzer;@ObservedObject var preferences:BackupPreferences;@ObservedObject var backup:BackupEngine;@ObservedObject var language:LanguageStore
    private var total:Int{analyzer.photoCount+analyzer.videoCount};private var protectedBytes:Int64{Int64(Double(analyzer.estimatedBytes)*Double(preferences.backupPercent)/100)};private var removableBytes:Int64{Int64(Double(protectedBytes)*Double(preferences.removalPercent)/100)}
    var body: some View {NavigationStack{ScrollView{VStack(alignment:.leading,spacing:18){Text(language.text("Free your space","Libérez votre espace")).font(.system(size:34,weight:.bold,design:.rounded));Text(language.text("Protect first. Remove locally only after verification.","Protégez d'abord. Retirez localement uniquement après vérification.")).foregroundStyle(.secondary);NavigationLink{StorageAnalysisView(language:language,backup:backup)}label:{HStack(spacing:14){ZStack{RoundedRectangle(cornerRadius:15).fill(Color.green.opacity(0.12)).frame(width:52,height:52);Image(systemName:"chart.bar.doc.horizontal.fill").foregroundStyle(.green).font(.title3)};VStack(alignment:.leading,spacing:4){Text(language.text("Analyze iPhone storage","Analyser le stockage de l’iPhone")).font(.headline).foregroundStyle(.primary);Text(language.text("Find screenshots, large videos and the files using the most space.","Trouvez les captures d’écran, les grosses vidéos et les fichiers qui prennent le plus de place.")).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.right").foregroundStyle(.secondary)}}.buttonStyle(.plain).card();VStack(alignment:.leading,spacing:16){Label(language.text("1. Protect in Libérons","1. Protéger dans Libérons"),systemImage:"icloud.and.arrow.up.fill").font(.headline).foregroundStyle(.blue);Text(storageSize(protectedBytes)).font(.system(size:40,weight:.bold,design:.rounded));Text(language.text("Estimated total size of selected photos and videos, including iCloud Photos originals when accessible. Not necessarily space occupied on this iPhone.","Taille totale estimée des photos et vidéos sélectionnées, y compris les originaux Photos iCloud accessibles. Ce n’est pas forcément l’espace occupé sur cet iPhone.")).font(.caption).foregroundStyle(.secondary);Text(language.text("about \(preferences.selectedCount(total:total).formatted()) items","environ \(preferences.selectedCount(total:total).formatted()) éléments")).foregroundStyle(.secondary);PercentPicker(selection:$preferences.backupPercent)}.card();BackupQueueView(backup:backup,preferences:preferences,analyzer:analyzer,language:language);VStack(alignment:.leading,spacing:16){Label(language.text("2. Free space on this iPhone","2. Libérer de l'espace sur cet iPhone"),systemImage:"iphone.and.arrow.forward").font(.headline).foregroundStyle(.green);Text(storageSize(removableBytes)).font(.system(size:40,weight:.bold,design:.rounded));Text(language.text("Selected protected media size, not guaranteed freeable iPhone storage. iCloud-optimized media may occupy much less space locally.","Taille des médias protégés sélectionnés, pas un gain de stockage garanti sur l’iPhone. Les médias optimisés via iCloud peuvent occuper beaucoup moins d’espace localement.")).font(.caption).foregroundStyle(.secondary);PercentPicker(selection:$preferences.removalPercent);Text(language.text("Only verified protected originals are eligible.","Seuls les originaux protégés et vérifiés sont éligibles.")).font(.caption).foregroundStyle(.secondary)}.card();FreeSpaceView(preferences:preferences,language:language,backup:backup)}.padding(20).padding(.bottom,100)}.background(LiberonsTheme.canvas).toolbar(.hidden,for:.navigationBar)}}
}

private struct AccountView: View {
    @ObservedObject var auth:AuthStore;@ObservedObject var cloud:CloudStorageSummary;@ObservedObject var language:LanguageStore
    @State private var showingLanguagePicker=false; @State private var localBytes:Int64=0; @State private var clearingCache=false; @State private var cacheMessage:String?
    @State private var openingReview=false
    @MainActor private func openReviewPage() async {
        guard !openingReview, let bundleID=Bundle.main.bundleIdentifier,
              var components=URLComponents(string:"https://itunes.apple.com/lookup") else { return }
        openingReview=true
        defer { openingReview=false }
        components.queryItems=[
            URLQueryItem(name:"bundleId",value:bundleID),
            URLQueryItem(name:"country",value:Locale.current.region?.identifier ?? "ca")
        ]
        guard let lookupURL=components.url else { return }
        do {
            let (data,_) = try await URLSession.shared.data(from:lookupURL)
            guard let json=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let app=(json["results"] as? [[String:Any]])?.first,
                  let trackID=app["trackId"] as? Int,
                  let reviewURL=URL(string:"https://apps.apple.com/app/id\(trackID)?action=write-review") else { return }
            await UIApplication.shared.open(reviewURL)
        } catch {
            // App Store lookup failures must not affect cloud storage or the account.
        }
    }
    private var email:String{auth.session?.user.email ?? "Libérons"};private var initials:String{String(email.prefix(1)).uppercased()};private var used:Int64{cloud.usedBytes};private var effectiveQuota:Int64{cloud.quotaBytes>0 ? cloud.quotaBytes:2_000_000_000};private var planDisplay:String{effectiveQuota<=2_050_000_000 ? language.text("Free · 2 GB","Gratuit · 2 Go"):storageName(effectiveQuota)}
    private var localDisplay:String{localBytes==0 ? language.text("0 KB","0 Ko"):ByteCountFormatter.string(fromByteCount:localBytes,countStyle:.file)}
    var body: some View {NavigationStack{ZStack{ScrollView{VStack(alignment:.leading,spacing:16){Text(language.text("Account","Compte")).font(.system(size:38,weight:.bold,design:.rounded));HStack(spacing:14){ZStack{Circle().fill(Color.blue.gradient).frame(width:58,height:58);Text(initials).font(.title2.bold()).foregroundStyle(.white)};VStack(alignment:.leading){Text(email).font(.headline).lineLimit(1);Text(language.text("Libérons account","Compte Libérons")).foregroundStyle(.secondary)};Spacer()}.card();VStack(alignment:.leading,spacing:14){HStack{Label(language.text("Libérons storage","Stockage Libérons"),systemImage:"icloud.fill").font(.headline).foregroundStyle(.blue);Spacer();Text(planDisplay).fontWeight(.bold)};ProgressView(value:min(1,Double(used)/Double(effectiveQuota))).tint(.blue);HStack{Text(language.text("Used","Utilisé"));Spacer();Text(used==0 ? language.text("0 KB","0 Ko"):storageName(used)).fontWeight(.semibold)};NavigationLink{StorageSharingView(cloud:cloud,language:language)}label:{HStack{Image(systemName:"person.2.fill").foregroundStyle(.blue);Text(language.text("Share my storage","Partager mon stockage"));Spacer();Image(systemName:"chevron.right")}}.foregroundStyle(.primary).padding(.top,8);NavigationLink{StoragePlanView(cloud:cloud,language:language)}label:{HStack{Text(language.text("Manage Libérons plan","Gérer le forfait Libérons"));Spacer();Image(systemName:"chevron.right")}}.foregroundStyle(.blue)}.card();VStack(alignment:.leading,spacing:13){HStack{Label(language.text("On-device storage","Stockage sur cet iPhone"),systemImage:"iphone").font(.headline);Spacer();Text(localDisplay).fontWeight(.semibold)};Text(language.text("Temporary cache used by Libérons on this iPhone. Your protected cloud originals are not stored here.","Cache temporaire utilisé par Libérons sur cet iPhone. Vos originaux protégés dans le cloud ne sont pas stockés ici.")).font(.caption).foregroundStyle(.secondary);Button{guard !clearingCache else{return};clearingCache=true;cacheMessage=nil;LocalStorageGuard.purgeTransientStorage();localBytes=LocalStorageGuard.reclaimableBytes();withAnimation(.easeInOut(duration:0.18)){cacheMessage=language.text("Cache cleared.","Cache vidé.")};clearingCache=false;Task{try? await Task.sleep(for:.seconds(3));await MainActor.run{withAnimation(.easeOut(duration:0.2)){cacheMessage=nil}}}}label:{HStack{if clearingCache{ProgressView().controlSize(.small)};Label(language.text("Clear cache","Vider le cache"),systemImage:"trash")}.frame(maxWidth:.infinity).frame(height:38)}.buttonStyle(.bordered).disabled(clearingCache||localBytes==0);if let cacheMessage{Text(cacheMessage).font(.caption).foregroundStyle(.green).transition(.opacity.combined(with:.move(edge:.top)))}}.card();VStack(spacing:0){Button{withAnimation(.spring(response:0.28,dampingFraction:0.88)){showingLanguagePicker=true}}label:{SettingRow(icon:"globe",title:language.text("Language","Langue"),trailing:language.language.title)}.buttonStyle(.plain);Divider();NavigationLink{LiberonsNotificationSettingsView(language:language)}label:{SettingRow(icon:"bell.fill",title:language.text("Notifications","Notifications"))}.buttonStyle(.plain);Divider();NavigationLink{AccountSecurityView(auth:auth,language:language)}label:{SettingRow(icon:"lock.shield.fill",title:language.text("Privacy & security","Confidentialité et sécurité"))}.buttonStyle(.plain)}.card();VStack(spacing:0){NavigationLink{LiberonsTutorialView(language:language)}label:{SettingRow(icon:"play.rectangle.fill",title:language.text("How to use Libérons","Comment utiliser Libérons"))}.buttonStyle(.plain);Divider();NavigationLink{LiberonsHelpSupportView(language:language)}label:{SettingRow(icon:"questionmark.circle.fill",title:language.text("Help & support","Aide et support"))}.buttonStyle(.plain);Divider();NavigationLink{LiberonsAboutView(language:language)}label:{SettingRow(icon:"info.circle.fill",title:language.text("About Libérons","À propos de Libérons"))}.buttonStyle(.plain);Divider();Button{Task{await openReviewPage()}}label:{SettingRow(icon:"star.bubble.fill",title:language.text("Rate Libérons","Noter Libérons"))}.buttonStyle(.plain).disabled(openingReview)}.card();Button(role:.destructive){Task{await auth.signOut()}}label:{Label(language.text("Sign out","Se déconnecter"),systemImage:"rectangle.portrait.and.arrow.right").fontWeight(.semibold).frame(maxWidth:.infinity).frame(height:48)}.buttonStyle(.bordered).tint(.red)}.padding(20).padding(.bottom,100)}.scrollDisabled(showingLanguagePicker).task{localBytes=LocalStorageGuard.reclaimableBytes()};if showingLanguagePicker{Color.black.opacity(0.28).ignoresSafeArea().onTapGesture{withAnimation(.easeOut(duration:0.18)){showingLanguagePicker=false}}.transition(.opacity);VStack(spacing:0){Text(language.text("Choose language","Choisir la langue")).font(.headline).padding(.top,20).padding(.bottom,12);Divider();ForEach(LanguageStore.Language.allCases){item in Button{language.language=item;withAnimation(.easeOut(duration:0.18)){showingLanguagePicker=false}}label:{HStack{Text(item.title).foregroundStyle(.primary);Spacer();if item==language.language{Image(systemName:"checkmark.circle.fill").foregroundStyle(.blue)}}.padding(.horizontal,20).frame(height:54)}.buttonStyle(.plain);if item.id != LanguageStore.Language.allCases.last?.id{Divider().padding(.leading,20)}};Divider();Button(language.text("Cancel","Annuler")){withAnimation(.easeOut(duration:0.18)){showingLanguagePicker=false}}.fontWeight(.semibold).frame(maxWidth:.infinity).frame(height:54)}.background(.regularMaterial,in:RoundedRectangle(cornerRadius:24,style:.continuous)).overlay(RoundedRectangle(cornerRadius:24,style:.continuous).stroke(Color.white.opacity(0.35),lineWidth:0.5)).shadow(radius:30,y:12).padding(.horizontal,34).transition(.scale(scale:0.92).combined(with:.opacity)).zIndex(10)}}.background(LiberonsTheme.canvas).toolbar(.hidden,for:.navigationBar)}}
    private func storageName(_ bytes:Int64)->String{if bytes>=999_000_000_000{return String(format:"%.0f %@",Double(bytes)/1_000_000_000_000,language.text("TB","To"))};if bytes>=1_000_000_000{return String(format:bytes%1_000_000_000==0 ? "%.0f %@":"%.2f %@",Double(bytes)/1_000_000_000,language.text("GB","Go"))};return ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)}
}


private struct StorageSharingView: View {
    @ObservedObject var cloud: CloudStorageSummary
    @ObservedObject var language: LanguageStore
    private struct Share: Decodable, Identifiable {
        let id: UUID
        let owner_id: UUID
        let recipient_id: UUID
        let limit_bytes: Int64
        let status: String
        let owner_email: String
        let recipient_email: String
        let used_bytes: Int64
    }
    private struct ShareUsage: Decodable {
        let share_id: UUID
        let protected_bytes: Int64
        let pending_bytes: Int64
        let trash_bytes: Int64
    }
    @State private var email = ""
    @State private var gigabytes = "50"
    @State private var shares: [Share] = []
    @State private var usages: [UUID: Int64] = [:]
    @State private var sharedUsage: Int64 = 0
    @State private var editingShare: Share?
    @State private var editedGigabytes = ""
    @State private var busy = false
    @State private var message: String?
    private func refreshShares() async {
        do {
            let response: [Share] = try await SupabaseService.client.rpc("liberons_my_storage_shares").execute().value
            let usageRows: [ShareUsage] = try await SupabaseService.client.from("liberons_storage_share_usage").select("share_id,protected_bytes,pending_bytes,trash_bytes").execute().value
            shares = response
            sharedUsage = response.filter { $0.owner_id == SupabaseService.client.auth.currentUser?.id && $0.status == "accepted" }.reduce(Int64(0)) { $0 + $1.used_bytes }
            usages = Dictionary(uniqueKeysWithValues: usageRows.map { ($0.share_id,$0.protected_bytes+$0.pending_bytes+$0.trash_bytes) })
        } catch { message = error.localizedDescription }
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await action(); message = nil; await refreshShares() }
            catch { message = error.localizedDescription }
            busy = false
        }
    }
    private func invite() {
        guard let gb = Int64(gigabytes), gb > 0, gb <= planCapacity / 1_000_000_000 else {
            message = language.text("Enter a valid amount within your paid plan.","Saisissez une capacité valide dans votre forfait payé.")
            return
        }
        let recipient = email.trimmingCharacters(in:.whitespacesAndNewlines)
        guard recipient.contains("@") else { message = language.text("Enter an email address.","Saisissez une adresse e-mail."); return }
        perform {
            _ = try await SupabaseService.client.rpc("liberons_share_invite",params:["p_email":recipient,"p_limit_bytes":String(gb*1_000_000_000)]).execute()
            email = ""
        }
    }
    private func respond(_ id: UUID,_ accept: Bool) {
        perform {
            _ = try await SupabaseService.client.rpc("liberons_share_respond",params:["p_share_id":id.uuidString,"p_accept":accept ? "true":"false"]).execute()
        }
    }
    private func changeLimit(_ share: Share) {
        guard let gb = Int64(editedGigabytes), gb > 0,
              gb <= planCapacity / 1_000_000_000,
              gb <= Int64.max / 1_000_000_000 else {
            message = language.text("Enter a valid limit within your paid plan.", "Saisissez une limite valide dans votre forfait payé.")
            return
        }
        let bytes = gb * 1_000_000_000
        let occupied = usages[share.id] ?? share.used_bytes
        guard bytes >= occupied else {
            message = language.text("The limit cannot be below already stored data.", "La limite ne peut pas être inférieure aux fichiers déjà stockés.")
            return
        }
        editingShare = nil
        perform {
            _ = try await SupabaseService.client.rpc("liberons_share_change_limit", params: ["p_share_id":share.id.uuidString, "p_new_limit_bytes":String(bytes)]).execute()
        }
    }
    private func cancel(_ id: UUID) {
        perform {
            _ = try await SupabaseService.client.rpc("liberons_share_cancel",params:["p_share_id":id.uuidString]).execute()
        }
    }
    private var isPaid: Bool { cloud.billedPlanPriceCents > 0 && cloud.billedPlanQuotaBytes > 2_050_000_000 }
    private var planCapacity: Int64 { max(0, cloud.billedPlanQuotaBytes) }
    private var paidRemaining: Int64 { max(0, planCapacity - cloud.usedBytes - sharedUsage) }
    private func preciseCapacity(_ bytes: Int64) -> String {
        if bytes >= 999_000_000_000 {
            return String(format: "%.0f %@", Double(bytes) / 1_000_000_000_000, language.text("TB","To"))
        }
        if bytes >= 1_000_000_000 {
            return String(format: bytes % 1_000_000_000 == 0 ? "%.0f %@" : "%.2f %@", Double(bytes) / 1_000_000_000, language.text("GB","Go"))
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    private func capacity(_ value: Int64) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "%.2f %@", Double(value) / 1_000_000_000_000, language.text("TB", "To"))
        }
        return String(format: "%.1f %@", Double(value) / 1_000_000_000, language.text("GB", "Go"))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.blue)
                    Text(language.text("More space, together.", "Plus d’espace, ensemble."))
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text(language.text(
                        "Share part or all of the storage you pay for with someone you trust. Your photos and files always remain private.",
                        "Partagez une partie ou la totalité de votre stockage payé avec une personne de confiance. Vos photos et fichiers restent toujours privés."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 26))
                VStack(alignment: .leading, spacing: 14) {
                    Label(language.text("Your paid storage", "Votre stockage payé"), systemImage: "icloud.fill")
                        .font(.headline)
                    HStack(alignment: .firstTextBaseline) {
                        Text(isPaid ? capacity(planCapacity) : language.text("No paid plan", "Aucun forfait payé"))
                            .font(.title2.bold())
                        Spacer()
                        if isPaid {
                            Text(language.text("PAID", "PAYÉ"))
                                .font(.caption2.bold())
                                .foregroundStyle(.blue)
                        }
                    }
                    if isPaid {
                        ProgressView(value: planCapacity > 0 ? min(1, Double(cloud.usedBytes + sharedUsage) / Double(planCapacity)) : 0)
                            .tint(.blue)
                        HStack {
                            Text(language.text("Currently available", "Actuellement disponible"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(preciseCapacity(paidRemaining)).fontWeight(.semibold)
                        }
                        .font(.subheadline)
                    }
                    Text(language.text(
                        "Storage offered by Libérons is personal and cannot be shared.",
                        "L’espace offert par Libérons est personnel et ne peut pas être partagé."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 14) {
                    Label(language.text("How sharing works", "Comment fonctionne le partage"), systemImage: "shield.lefthalf.filled")
                        .font(.headline)
                    sharingRule("person.crop.circle.badge.checkmark",
                        language.text("An invitation, your choice", "Une invitation, votre choix"),
                        language.text("The person you invite can accept or decline.", "La personne invitée peut accepter ou refuser."))
                    Divider()
                    sharingRule("externaldrive",
                        language.text("One shared capacity", "Un seul espace partagé"),
                        language.text("Both people use the same paid storage. No extra capacity is created.", "Les deux personnes utilisent le même stockage payé. Aucun espace supplémentaire n’est créé."))
                    Divider()
                    sharingRule("slider.horizontal.3",
                        language.text("Stay in control", "Gardez le contrôle"),
                        language.text("Increase the shared amount whenever your plan allows. You can reduce it without affecting files already protected.", "Augmentez le partage selon votre forfait. Vous pouvez le réduire sans toucher aux fichiers déjà protégés."))
                    Divider()
                    sharingRule("lock.shield",
                        language.text("Your memories stay yours", "Vos souvenirs restent privés"),
                        language.text("Neither person can see the other's photos or files.", "Aucune des deux personnes ne peut consulter les photos ou fichiers de l’autre."))
                }
                .padding(20)
                .background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 12) {
                    Label(language.text("Invite someone", "Inviter une personne"),systemImage:"envelope.fill").font(.headline)
                    TextField(language.text("Their account email", "E-mail de son compte"),text:$email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField(language.text("GB", "Go"),text:$gigabytes).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        Text(language.text("GB maximum", "Go maximum")).font(.caption).foregroundStyle(.secondary)
                    }
                    Button(language.text("Send invitation", "Envoyer l’invitation")) { invite() }
                        .buttonStyle(.borderedProminent).disabled(!isPaid || busy)
                    if !isPaid { Text(language.text("An active paid plan is required to invite someone.","Un forfait payé actif est nécessaire pour inviter quelqu’un.")).font(.caption).foregroundStyle(.secondary) }
                }.padding(20).background(LiberonsTheme.card,in:RoundedRectangle(cornerRadius:24))
                VStack(alignment:.leading,spacing:14) {
                    HStack {
                        Label(language.text("Invitations and shares","Invitations et partages"),systemImage:"person.2.fill").font(.headline)
                        Spacer()
                        Button { Task { await refreshShares() } } label: { Image(systemName:"arrow.clockwise") }.disabled(busy)
                    }
                    if shares.isEmpty { Text(language.text("No invitations yet.","Aucune invitation pour le moment.")).foregroundStyle(.secondary) }
                    ForEach(shares) { share in
                        let owner = share.owner_id == SupabaseService.client.auth.currentUser?.id
                        let used = usages[share.id] ?? share.used_bytes
                        let remaining = max(0, share.limit_bytes - used)
                        VStack(alignment:.leading,spacing:14) {
                            HStack(spacing:12) {
                                Image(systemName:owner ? "person.crop.circle.badge.checkmark" : "person.2.fill")
                                    .font(.title2).foregroundStyle(.blue)
                                    .frame(width:44,height:44)
                                    .background(Color.blue.opacity(0.10),in:RoundedRectangle(cornerRadius:14))
                                VStack(alignment:.leading,spacing:4) {
                                    Text(owner ? language.text("Shared with","Partagé avec") : language.text("Invitation from","Invitation de"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(owner ? share.recipient_email : share.owner_email)
                                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                                        .textSelection(.enabled)
                                }
                                Spacer(minLength:0)
                            }
                            HStack {
                                Text(share.status == "accepted" ? language.text("Active sharing","Partage actif") : share.status == "pending" ? language.text("Pending invitation","Invitation en attente") : share.status.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(share.status == "accepted" ? .green : .orange)
                                Spacer()
                                Text(capacity(share.limit_bytes)).font(.subheadline.bold())
                            }
                            ProgressView(value:share.limit_bytes > 0 ? min(1,Double(used)/Double(share.limit_bytes)) : 0)
                                .tint(.blue)
                            HStack {
                                VStack(alignment:.leading,spacing:3) {
                                    Text(language.text("Used by recipient","Utilisé par le bénéficiaire")).font(.caption2).foregroundStyle(.secondary)
                                    Text(capacity(used)).font(.subheadline.weight(.semibold))
                                }
                                Spacer()
                                VStack(alignment:.trailing,spacing:3) {
                                    Text(language.text("Remaining within limit","Reste sur la limite")).font(.caption2).foregroundStyle(.secondary)
                                    Text(capacity(remaining)).font(.subheadline.weight(.semibold))
                                }
                            }
                            if share.status == "accepted" && !owner {
                                let selected = UserDefaults.standard.string(forKey:"liberons_active_share_\(share.recipient_id.uuidString)") == share.id.uuidString
                                Button(selected ? language.text("Use my own storage","Utiliser mon stockage") : language.text("Use this shared storage","Utiliser ce stockage partagé")) {
                                    let key="liberons_active_share_\(share.recipient_id.uuidString)"
                                    if selected { UserDefaults.standard.removeObject(forKey:key) }
                                    else { UserDefaults.standard.set(share.id.uuidString,forKey:key) }
                                    Task { await refreshShares() }
                                }.buttonStyle(.bordered)
                            }
                            if share.status == "pending" && !owner {
                                HStack {
                                    Button(language.text("Accept","Accepter")) { respond(share.id,true) }.buttonStyle(.borderedProminent)
                                    Button(language.text("Decline","Refuser")) { respond(share.id,false) }.buttonStyle(.bordered)
                                }.disabled(busy)
                            }
                            if share.status == "accepted" && owner {
                                Button {
                                    editedGigabytes = String(share.limit_bytes / 1_000_000_000)
                                    editingShare = share
                                } label: {
                                    Label(language.text("Adjust shared limit", "Modifier la limite partagée"), systemImage: "slider.horizontal.3")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(busy)
                                Button(language.text("Stop sharing","Arrêter le partage"),role:.destructive) { cancel(share.id) }.disabled(busy)
                            }
                        }
                        .padding(16)
                        .background(Color.blue.opacity(0.045),in:RoundedRectangle(cornerRadius:20))
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.red) }
                    if busy { ProgressView() }
                }.padding(20).background(LiberonsTheme.card,in:RoundedRectangle(cornerRadius:24))
            }
            .padding(20)
        }
        .background(LiberonsTheme.canvas)
        .alert(language.text("Shared storage limit", "Limite du stockage partagé"), isPresented: Binding(get: { editingShare != nil }, set: { if !$0 { editingShare = nil } })) {
            TextField(language.text("Maximum GB", "Maximum en Go"), text: $editedGigabytes)
                .keyboardType(.numberPad)
            Button(language.text("Cancel", "Annuler"), role: .cancel) { editingShare = nil }
            Button(language.text("Save", "Enregistrer")) {
                if let share = editingShare { changeLimit(share) }
            }
        } message: {
            Text(language.text("Enter the maximum storage this person can use. Existing files remain protected.", "Indiquez le stockage maximal autorisé. Les fichiers existants restent protégés."))
        }
        .navigationTitle(language.text("Share storage", "Partager le stockage"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await cloud.refresh(); await refreshShares() }
    }
    private func sharingRule(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.blue).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StoragePlanView: View {
    @ObservedObject var cloud:CloudStorageSummary;@ObservedObject var language:LanguageStore
    @State private var catalogPrices: [String: CatalogPrice] = [:]
    @State private var sharedUsage: Int64 = 0
    @State private var sharedCount = 0
    private struct OwnedShare: Decodable { let owner_id: UUID; let status: String; let used_bytes: Int64 }
    private func refreshSharedUsage() async {
        do {
            let rows: [OwnedShare] = try await SupabaseService.client.rpc("liberons_my_storage_shares").execute().value
            let mine = rows.filter { $0.owner_id == SupabaseService.client.auth.currentUser?.id && $0.status == "accepted" }
            sharedUsage = mine.reduce(Int64(0)) { $0 + $1.used_bytes }
            sharedCount = mine.count
        } catch { }
    }

    private struct CatalogPrice: Decodable {
        let code: String
        let monthly_price_cents: Int
        let currency: String
    }

    private func refreshCatalogPrices() async {
        do {
            let rows: [CatalogPrice] = try await SupabaseService.client
                .from("public_subscription_plans")
                .select("code,monthly_price_cents,currency")
                .execute().value
            catalogPrices = Dictionary(uniqueKeysWithValues: rows.map { ($0.code, $0) })
        } catch {
            // Keep the bundled launch prices available while offline.
        }
    }

    private var used:Int64{cloud.usedBytes + sharedUsage};private var effectiveQuota:Int64{cloud.quotaBytes};private var available:Int64{max(0,effectiveQuota-used)}
    private let plans:[(code:String,gb:Int,bytes:Int64,price:String,detailEN:String,detailFR:String,popular:Bool)]=[("free",2,2_000_000_000,"Free","Discover Libérons.","Pour découvrir Libérons.",false),("50gb",50,50_000_000_000,"$2.99/month","For your photos and videos.","Pour vos photos et vidéos.",false),("100gb",100,100_000_000_000,"$3.99/month","For all your memories.","Pour tous vos souvenirs.",false),("250gb",250,250_000_000_000,"$5.99/month","The ideal balance for photos and videos.","Le meilleur équilibre photos et vidéos.",true),("500gb",500,500_000_000_000,"$7.99/month","For a large library.","Pour une grande bibliothèque.",false),("1tb",1000,1_000_000_000_000,"$12.99/month","Keep everything, without compromise.","Pour tout garder, sans compromis.",false),("2tb",2000,2_000_000_000_000,"$21.99/month","For large photo and video libraries.","Pour les grandes photothèques.",false),("5tb",5000,5_000_000_000_000,"$54.99/month","For a library that keeps growing.","Pour une bibliothèque qui ne cesse de grandir.",false),("10tb",10000,10_000_000_000_000,"$109.99/month","For your largest library.","Pour votre plus grande bibliothèque.",false)]
    var body: some View {ScrollView{VStack(alignment:.leading,spacing:18){VStack(alignment:.leading,spacing:14){HStack{Image(systemName:"icloud.fill").font(.title).foregroundStyle(.blue);VStack(alignment:.leading,spacing:3){Text(language.text("Total Libérons capacity","Capacité totale Libérons")).font(.caption).foregroundStyle(.secondary);Text(capacityName).font(.title2.bold())};Spacer();Text(language.text("ACTIVE","ACTIF")).font(.caption2.bold()).foregroundStyle(.blue).padding(.horizontal,9).padding(.vertical,6).background(Color.blue.opacity(0.10),in:Capsule())};if cloud.hasGrantedBonus{HStack(spacing:9){Image(systemName:"gift.fill").foregroundStyle(.green);VStack(alignment:.leading,spacing:2){Text(language.text("Extra storage offered by Libérons","Espace supplémentaire offert par Libérons")).font(.subheadline.weight(.semibold));Text("+\(storageName(cloud.grantedBonusBytes))").font(.caption).foregroundStyle(.secondary)}}.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.green.opacity(0.08),in:RoundedRectangle(cornerRadius:16,style:.continuous))};ProgressView(value:effectiveQuota>0 ? min(1,Double(used)/Double(effectiveQuota)):0).tint(.blue);HStack{VStack(alignment:.leading){Text(language.text("Used","Utilisé")).font(.caption).foregroundStyle(.secondary);Text(used==0 ? language.text("0 KB","0 Ko"):storageName(used)).fontWeight(.semibold)};Spacer();VStack(alignment:.trailing){Text(language.text("Available","Disponible")).font(.caption).foregroundStyle(.secondary);Text(storageName(available)).fontWeight(.semibold)}}}.card();if sharedCount > 0 {
        VStack(alignment:.leading,spacing:12) {
            Label(language.text("Shared storage consumption","Consommation du stockage partagé"),systemImage:"person.2.fill").font(.headline)
            HStack { Text(language.text("Your files","Vos fichiers")); Spacer(); Text(storageName(cloud.usedBytes)).fontWeight(.semibold) }
            HStack { Text(language.text("Recipients","Bénéficiaires") + " (\(sharedCount))"); Spacer(); Text(storageName(sharedUsage)).fontWeight(.semibold) }
            Divider()
            HStack { Text(language.text("Total used","Total utilisé")).fontWeight(.semibold); Spacer(); Text(storageName(used)).fontWeight(.bold) }
            Text(language.text("All participants use the same paid storage.","Tous les participants utilisent le même stockage payé.")).font(.caption).foregroundStyle(.secondary)
        }.card()
    };VStack(alignment:.leading,spacing:12){Text(language.text("Your billed plan","Votre forfait facturé")).font(.title3.bold());HStack(spacing:13){ZStack{RoundedRectangle(cornerRadius:13).fill(Color.blue.opacity(0.12)).frame(width:46,height:46);Image(systemName:"creditcard.fill").foregroundStyle(.blue)};VStack(alignment:.leading,spacing:4){HStack(spacing:7){Text(billedPlanName).font(.headline);Text(language.text("CURRENT","ACTUEL")).font(.caption2.bold()).foregroundStyle(.blue).padding(.horizontal,7).padding(.vertical,3).background(Color.blue.opacity(0.10),in:Capsule())};Text(billedPrice).font(.subheadline.bold());Text(cloud.hasGrantedBonus ? language.text("This is the plan you actually pay for. Any space offered by Libérons does not change its price.","C’est le forfait que vous payez réellement. L’espace offert par Libérons ne change pas son prix.") : language.text("This is the plan you currently pay for.","C’est le forfait que vous payez actuellement.")).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"checkmark.circle.fill").foregroundStyle(.blue).font(.title3)}}.card();VStack(alignment:.leading,spacing:12){Text(language.text("Available plans","Forfaits disponibles")).font(.title3.bold());Text(language.text("Monthly Libérons plans.","Forfaits mensuels Libérons.")).font(.subheadline).foregroundStyle(.secondary);ForEach(Array(plans.enumerated()),id:\.offset){index,plan in if index>0{Divider()};HStack(spacing:13){ZStack{RoundedRectangle(cornerRadius:13).fill(isBilledPlan(plan) ? Color.blue.opacity(0.12):Color.secondary.opacity(0.08)).frame(width:46,height:46);Image(systemName:plan.bytes>=1_000_000_000_000 ? "externaldrive.fill":"icloud.fill").foregroundStyle(isBilledPlan(plan) ? .blue:.secondary)};VStack(alignment:.leading,spacing:4){HStack(spacing:7){Text(planName(plan)).font(.headline);if plan.popular{Text(language.text("MOST POPULAR","PLUS POPULAIRE")).font(.system(size:9,weight:.bold)).foregroundStyle(.white).padding(.horizontal,7).padding(.vertical,3).background(Color.blue,in:Capsule())};if isBilledPlan(plan){Text(language.text("Current","Actuel")).font(.caption2.bold()).foregroundStyle(.blue).padding(.horizontal,7).padding(.vertical,3).background(Color.blue.opacity(0.10),in:Capsule())}};Text(localizedPrice(plan.price, code: plan.code)).font(.subheadline.bold()).foregroundStyle(plan.price=="Free" ? .green:.primary);Text(language.text(plan.detailEN,plan.detailFR)).font(.caption).foregroundStyle(.secondary)};Spacer();if isBilledPlan(plan){Image(systemName:"checkmark.circle.fill").foregroundStyle(.blue).font(.title3)}}.padding(.vertical,5)}}.card();VStack(alignment:.leading,spacing:12){Label(language.text("Your Libérons protection","Votre protection Libérons"),systemImage:"checkmark.shield.fill").font(.headline).foregroundStyle(.green);HStack{Text(language.text("Protected memories","Souvenirs protégés"));Spacer();Text(cloud.protectedCount.formatted()).fontWeight(.semibold)};if cloud.pendingBytes>0{Divider();HStack{Text(language.text("Unfinished backups (not actively uploading)","Sauvegardes inachevées (aucun transfert confirmé)"));Spacer();Text(storageName(cloud.pendingBytes)).fontWeight(.semibold)}}}.card();Button{Task{await cloud.refresh()}}label:{Label(language.text("Refresh plan status","Actualiser l’état du forfait"),systemImage:"arrow.clockwise").frame(maxWidth:.infinity).frame(height:42)}.buttonStyle(.borderedProminent).disabled(cloud.isLoading)}.padding(20)}.background(LiberonsTheme.canvas).navigationTitle(language.text("Libérons plan","Forfait Libérons")).navigationBarTitleDisplayMode(.inline).task { await refreshCatalogPrices(); await refreshSharedUsage() }}
    private var capacityName:String{storageName(effectiveQuota)}
    private var billedPlanName:String{if let plan=plans.first(where:{isBilledPlan($0)}){return plan.price=="Free" ? language.text("Free · 2 GB","Gratuit · 2 Go"):planName(plan)};return storageName(cloud.billedPlanQuotaBytes)}
    private var billedPrice:String{if cloud.billedPlanPriceCents<=0{return language.text("Free","Gratuit")};let value=Double(cloud.billedPlanPriceCents)/100;let amount=String(format:"%.2f",value);return language.language == .french ? "\(amount.replacingOccurrences(of:".",with:",")) $ US / mois" : "$\(amount) USD / month"}
    private func planName(_ plan:(code:String,gb:Int,bytes:Int64,price:String,detailEN:String,detailFR:String,popular:Bool))->String{if plan.gb>=1000{let tb=plan.gb/1000;return language.text("\(tb) TB","\(tb) To")};return language.text("\(plan.gb) GB","\(plan.gb) Go")}
    private func isBilledPlan(_ plan:(code:String,gb:Int,bytes:Int64,price:String,detailEN:String,detailFR:String,popular:Bool))->Bool{let normalized=cloud.billedPlanCode.lowercased().replacingOccurrences(of:"_",with:"").replacingOccurrences(of:"-",with:"");let planCode=plan.code.lowercased().replacingOccurrences(of:"_",with:"").replacingOccurrences(of:"-",with:"");if normalized==planCode{return true};let tolerance=max(Int64(50_000_000),plan.bytes/100);return abs(cloud.billedPlanQuotaBytes-plan.bytes)<=tolerance}
    private func storageName(_ bytes:Int64)->String{if bytes>=999_000_000_000{return String(format:"%.0f %@",Double(bytes)/1_000_000_000_000,language.text("TB","To"))};if bytes>=1_000_000_000{return String(format:bytes%1_000_000_000==0 ? "%.0f %@":"%.2f %@",Double(bytes)/1_000_000_000,language.text("GB","Go"))};return ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)}
    private func localizedPrice(_ fallback: String, code: String) -> String {
        if fallback == "Free" { return language.text("Free", "Gratuit") }
        let row = catalogPrices[code]
        let fallbackAmount = fallback.dropFirst().split(separator: "/").first.map(String.init) ?? ""
        let amount = row.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double($0.monthly_price_cents) / 100) } ?? fallbackAmount
        let currency = row?.currency ?? "USD"
        let frenchCurrency = currency == "USD" ? "US" : currency
        return language.text("$\(amount) \(currency) / month", "\(amount.replacingOccurrences(of: ".", with: ",")) $ \(frenchCurrency) / mois")
    }
}

private struct PercentPicker:View{@Binding var selection:Int;var body:some View{HStack(spacing:8){ForEach(BackupPreferences.choices,id:\.self){value in Button("\(value)%"){selection=value}.buttonStyle(.borderedProminent).tint(selection==value ? .blue:.gray)}}}}
private struct Metric:View{let icon:String;let value:String;let label:String;let tint:Color;var body:some View{VStack(alignment:.leading,spacing:8){Image(systemName:icon).foregroundStyle(tint);Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.65);Text(label).font(.caption).foregroundStyle(.secondary)}.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(LiberonsTheme.insetCard,in:RoundedRectangle(cornerRadius:20))}}
private struct DeviceMediaMetric:View{let value:String;let label:String;var body:some View{VStack(alignment:.leading,spacing:8){HStack(spacing:6){Image(systemName:"photo.fill").foregroundStyle(.orange);Image(systemName:"video.fill").foregroundStyle(.purple)};Text(value).font(.title3.bold());Text(label).font(.caption).foregroundStyle(.secondary)}.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(LiberonsTheme.insetCard,in:RoundedRectangle(cornerRadius:20))}}
private struct SettingRow:View{let icon:String;let title:String;var trailing:String?=nil;var body:some View{HStack(spacing:13){Image(systemName:icon).frame(width:25).foregroundStyle(.blue);Text(title);Spacer();if let trailing{Text(trailing).foregroundStyle(.secondary)};Image(systemName:"chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,15).contentShape(Rectangle())}}
private extension View{func card()->some View{self.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(LiberonsTheme.card,in:RoundedRectangle(cornerRadius:26,style:.continuous)).shadow(color:.black.opacity(0.04),radius:16,y:6)}}