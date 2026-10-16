import SwiftUI
import Photos

struct BackupQueueView: View {
    @ObservedObject var backup: BackupEngine
    @ObservedObject var preferences: BackupPreferences
    @ObservedObject var analyzer: PhotoLibraryAnalyzer
    @ObservedObject var language: LanguageStore
    @State private var showMediaPicker = false
    @State private var showPostBackupCleanup = false
    @State private var deletingProtectedBatch = false
    @State private var cleanupError: String?

    private var requestedCount: Int { max(1, preferences.selectedCount(total: analyzer.photoCount + analyzer.videoCount)) }
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

            Text(language.text("You stay in control: choose specific photos and videos, or let Libérons start automatically with the oldest memories.", "Vous gardez le contrôle : choisissez précisément vos photos et vidéos, ou laissez Libérons commencer automatiquement par les souvenirs les plus anciens.")).font(.subheadline).foregroundStyle(.secondary)

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
            Text(language.text("Automatic option", "Option automatique")).font(.caption.bold()).foregroundStyle(.secondary)
            Text(language.text("Protect about \(requestedCount) items, oldest first.", "Protéger environ \(requestedCount) éléments, en commençant par les plus anciens.")).font(.caption).foregroundStyle(.secondary)
            Button { Task { await backup.backupOldestItems(count: requestedCount) } } label: { HStack { Spacer(); if backup.isRunning { ProgressView().tint(.white) }; Text(backup.isRunning ? language.text("Backup in progress…", "Sauvegarde en cours…") : language.text("Protect oldest items", "Protéger les plus anciens")).fontWeight(.semibold); Spacer() }.frame(height: 34) }.buttonStyle(.bordered).controlSize(.large).disabled(backup.isRunning || !analyzer.canReadLibrary)

            Text(language.text("Nothing is deleted automatically. Libérons asks first after cloud protection is verified.", "Rien n’est supprimé automatiquement. Libérons vous demande d’abord après vérification de la protection cloud.")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 18, y: 7)
        .sheet(isPresented: $showMediaPicker) { MediaSelectionView(backup: backup, language: language) }
        .onChange(of: backup.protectionBatchID) { _, _ in if !backup.newlyProtectedLocalIdentifiers.isEmpty { showPostBackupCleanup = true } }
        .confirmationDialog(language.text("Free space on this iPhone?", "Libérer de l’espace sur cet iPhone ?"), isPresented: $showPostBackupCleanup, titleVisibility: .visible) {
            Button(language.text("Remove protected originals", "Supprimer les originaux protégés"), role: .destructive) { Task { await removeProtectedBatchFromDevice() } }
            Button(language.text("Keep them on iPhone", "Les garder sur l’iPhone"), role: .cancel) { }
        } message: { Text(language.text("These items are verified in Libérons Cloud. Apple will ask you to confirm their removal from Photos. Their Libérons copies stay protected.", "Ces éléments sont vérifiés dans Libérons Cloud. Apple vous demandera de confirmer leur suppression dans Photos. Leurs copies Libérons restent protégées.")) }
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
