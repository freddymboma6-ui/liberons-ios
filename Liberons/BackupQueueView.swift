import SwiftUI
import Photos

struct BackupQueueView: View {
    @ObservedObject var backup: BackupEngine
    @ObservedObject var preferences: BackupPreferences
    @ObservedObject var analyzer: PhotoLibraryAnalyzer
    @ObservedObject var language: LanguageStore
    @State private var showMediaPicker = false
    @State private var showBackupReview = false
    @State private var showBackupConfirmation = false
    @State private var showPostBackupCleanup = false
    @State private var deletingProtectedBatch = false
    @State private var cleanupError: String?

    private var totalLibraryCount: Int { analyzer.photoCount + analyzer.videoCount }
    private var requestedCount: Int { max(1, preferences.selectedCount(total: totalLibraryCount)) }
    private var estimatedBytes: Int64 {
        guard totalLibraryCount > 0 else { return 0 }
        let average = Double(analyzer.estimatedBytes) / Double(totalLibraryCount)
        return Int64(average * Double(min(requestedCount, totalLibraryCount)))
    }
    private var estimatedSize: String { ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file) }
    private var protectedStillOnDevice: [PHAsset] {
        guard !backup.newlyProtectedLocalIdentifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: backup.newlyProtectedLocalIdentifiers, options: nil)
        var assets: [PHAsset] = []; result.enumerateObjects { asset, _, _ in assets.append(asset) }; return assets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(language.text("Choose what to protect", "Choisir quoi protéger"), systemImage: "checkmark.circle.fill").font(.headline)
                Spacer()
                if backup.queueTotal > 0 { Text("\(backup.queueCompleted + backup.queueFailed)/\(backup.queueTotal)").font(.subheadline.bold()).monospacedDigit() }
            }

            Text(language.text("You stay in control: choose specific photos and videos, or prepare an automatic selection from the percentage above.", "Vous gardez le contrôle : choisissez précisément vos photos et vidéos, ou préparez une sélection automatique à partir du pourcentage choisi plus haut.")).font(.subheadline).foregroundStyle(.secondary)

            Button { showMediaPicker = true } label: { Label(language.text("Choose photos and videos", "Choisir les photos et vidéos"), systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity).frame(height: 34) }.buttonStyle(.borderedProminent).controlSize(.large).disabled(backup.isRunning || !analyzer.canReadLibrary)

            if backup.queueTotal > 0 {
                ProgressView(value: backup.queueProgress).tint(.blue)
                HStack(spacing: 14) {
                    Label("\(backup.queueCompleted) " + language.text("protected", "protégés"), systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                    if backup.queueFailed > 0 { Label("\(backup.queueFailed) " + language.text("failed", "échoués"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }.font(.caption.bold())
                if let name = backup.currentQueueFilename { Text(language.text("Now: ", "En cours : ") + name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }

            if !backup.newlyProtectedLocalIdentifiers.isEmpty && !protectedStillOnDevice.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label(language.text("Already protected in Libérons", "Déjà protégés dans Libérons"), systemImage: "checkmark.shield.fill").font(.subheadline.bold()).foregroundStyle(.green)
                    Text(language.text("\(protectedStillOnDevice.count) protected item(s) are still in Apple Photos. You can keep them there or free the local space now.", "\(protectedStillOnDevice.count) élément(s) protégé(s) sont encore dans Photos. Vous pouvez les garder ou libérer l’espace local maintenant.")).font(.caption).foregroundStyle(.secondary)
                    Button(role: .destructive) { showPostBackupCleanup = true } label: { Label(language.text("Remove protected originals from iPhone", "Supprimer les originaux protégés de l’iPhone"), systemImage: "iphone.slash").frame(maxWidth: .infinity).frame(height: 34) }.buttonStyle(.bordered).disabled(deletingProtectedBatch)
                    if let cleanupError { Text(cleanupError).font(.caption).foregroundStyle(.red) }
                }
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("Automatic selection", "Sélection automatique")).font(.caption.bold()).foregroundStyle(.secondary)
                    Text("\(preferences.backupPercent)% · " + language.text("about \(requestedCount.formatted()) items", "environ \(requestedCount.formatted()) éléments")).font(.subheadline.bold())
                    Text(language.text("Estimated \(estimatedSize), oldest memories first.", "Environ \(estimatedSize), en commençant par les souvenirs les plus anciens.")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button { showBackupReview = true } label: {
                Label(language.text("Continue", "Continuer"), systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity).frame(height: 34)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(backup.isRunning || !analyzer.canReadLibrary || totalLibraryCount == 0)

            Text(language.text("Choosing a percentage never starts a backup. Libérons shows a review first, then asks you to confirm.", "Choisir un pourcentage ne lance jamais une sauvegarde. Libérons affiche d’abord un récapitulatif, puis vous demande de confirmer.")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 18, y: 7)
        .sheet(isPresented: $showMediaPicker) { MediaSelectionView(backup: backup, language: language) }
        .sheet(isPresented: $showBackupReview) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "icloud.and.arrow.up.fill").font(.system(size: 44)).foregroundStyle(.blue)
                    Text(language.text("Ready to protect", "Prêt à protéger")).font(.largeTitle.bold())
                    Text(language.text("Review your automatic selection before Libérons starts uploading anything.", "Vérifiez votre sélection automatique avant que Libérons commence la moindre sauvegarde.")).foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        reviewRow(language.text("Selected percentage", "Pourcentage choisi"), "\(preferences.backupPercent)%")
                        Divider()
                        reviewRow(language.text("Estimated items", "Éléments estimés"), requestedCount.formatted())
                        Divider()
                        reviewRow(language.text("Estimated size", "Taille estimée"), estimatedSize)
                        Divider()
                        reviewRow(language.text("Order", "Ordre"), language.text("Oldest first", "Plus anciens d’abord"))
                    }
                    .padding(.horizontal, 18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))

                    Label(language.text("Nothing will be removed from your iPhone during this step.", "Rien ne sera retiré de votre iPhone pendant cette étape."), systemImage: "iphone").font(.footnote).foregroundStyle(.secondary)
                    Label(language.text("After protection is verified, Libérons will ask separately before offering to free local space.", "Une fois la protection vérifiée, Libérons demandera séparément votre accord avant de proposer de libérer l’espace local."), systemImage: "checkmark.shield.fill").font(.footnote).foregroundStyle(.secondary)

                    Spacer()
                    Button { showBackupReview = false; showBackupConfirmation = true } label: {
                        Text(language.text("Continue", "Continuer")).fontWeight(.bold).frame(maxWidth: .infinity).frame(height: 48)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button(language.text("Cancel", "Annuler")) { showBackupReview = false }.frame(maxWidth: .infinity)
                }
                .padding(24)
                .navigationTitle(language.text("Review", "Récapitulatif"))
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(language.text("Start this backup?", "Commencer cette sauvegarde ?"), isPresented: $showBackupConfirmation, titleVisibility: .visible) {
            Button(language.text("Start protection", "Commencer la protection")) { Task { await backup.backupOldestItems(count: requestedCount) } }
            Button(language.text("Cancel", "Annuler"), role: .cancel) {}
        } message: {
            Text(language.text("Libérons will protect about \(requestedCount.formatted()) items. No local original will be deleted by starting this backup.", "Libérons va protéger environ \(requestedCount.formatted()) éléments. Aucun original local ne sera supprimé en lançant cette sauvegarde."))
        }
        .onChange(of: backup.protectionBatchID) { _, _ in if !backup.newlyProtectedLocalIdentifiers.isEmpty { showPostBackupCleanup = true } }
        .confirmationDialog(language.text("Free space on this iPhone?", "Libérer de l’espace sur cet iPhone ?"), isPresented: $showPostBackupCleanup, titleVisibility: .visible) {
            Button(language.text("Remove protected originals", "Supprimer les originaux protégés"), role: .destructive) { Task { await removeProtectedBatchFromDevice() } }
            Button(language.text("Keep them on iPhone", "Les garder sur l’iPhone"), role: .cancel) { }
        } message: { Text(language.text("These items are verified in Libérons Cloud. Apple will ask you to confirm their removal from Photos. Their Libérons copies stay protected.", "Ces éléments sont vérifiés dans Libérons Cloud. Apple vous demandera de confirmer leur suppression dans Photos. Leurs copies Libérons restent protégées.")) }
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing) }.padding(.vertical, 15)
    }

    @MainActor private func removeProtectedBatchFromDevice() async {
        let assets = protectedStillOnDevice
        guard !assets.isEmpty else { backup.clearPostBackupOffer(); return }
        deletingProtectedBatch = true; cleanupError = nil
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets as NSArray) }
            deletingProtectedBatch = false
            backup.clearPostBackupOffer()
        } catch {
            deletingProtectedBatch = false
            cleanupError = error.localizedDescription
        }
    }
}
