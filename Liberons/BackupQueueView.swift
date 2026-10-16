import SwiftUI

struct BackupQueueView: View {
    @ObservedObject var backup: BackupEngine
    @ObservedObject var preferences: BackupPreferences
    @ObservedObject var analyzer: PhotoLibraryAnalyzer
    @ObservedObject var language: LanguageStore
    @State private var showMediaPicker = false

    private var requestedCount: Int { max(1, preferences.selectedCount(total: analyzer.photoCount + analyzer.videoCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(language.text("Choose what to protect", "Choisir quoi protéger"), systemImage: "checkmark.circle.fill").font(.headline)
                Spacer()
                if backup.queueTotal > 0 { Text("\(backup.queueCompleted + backup.queueFailed)/\(backup.queueTotal)").font(.subheadline.bold()).monospacedDigit() }
            }

            Text(language.text("You stay in control: choose specific photos and videos, or let Libérons start automatically with the oldest memories.", "Vous gardez le contrôle : choisissez précisément vos photos et vidéos, ou laissez Libérons commencer automatiquement par les souvenirs les plus anciens.")).font(.subheadline).foregroundStyle(.secondary)

            Button { showMediaPicker = true } label: {
                Label(language.text("Choose photos and videos", "Choisir les photos et vidéos"), systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity).frame(height: 34)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(backup.isRunning || !analyzer.canReadLibrary)

            if backup.queueTotal > 0 {
                ProgressView(value: backup.queueProgress).tint(.blue)
                HStack(spacing: 14) {
                    Label("\(backup.queueCompleted) " + language.text("protected", "protégés"), systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                    if backup.queueFailed > 0 { Label("\(backup.queueFailed) " + language.text("failed", "échoués"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }.font(.caption.bold())
                if let name = backup.currentQueueFilename { Text(language.text("Now: ", "En cours : ") + name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }

            Divider()
            Text(language.text("Automatic option", "Option automatique")).font(.caption.bold()).foregroundStyle(.secondary)
            Text(language.text("Protect about \(requestedCount) items, oldest first.", "Protéger environ \(requestedCount) éléments, en commençant par les plus anciens.")).font(.caption).foregroundStyle(.secondary)
            Button { Task { await backup.backupOldestItems(count: requestedCount) } } label: {
                HStack { Spacer(); if backup.isRunning { ProgressView().tint(.white) }; Text(backup.isRunning ? language.text("Backup in progress…", "Sauvegarde en cours…") : language.text("Protect oldest items", "Protéger les plus anciens")).fontWeight(.semibold); Spacer() }.frame(height: 34)
            }.buttonStyle(.bordered).controlSize(.large).disabled(backup.isRunning || !analyzer.canReadLibrary)

            Text(language.text("Nothing is deleted from this iPhone during backup.", "Rien n'est supprimé de cet iPhone pendant la sauvegarde.")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 18, y: 7)
        .sheet(isPresented: $showMediaPicker) { MediaSelectionView(backup: backup, language: language) }
    }
}
