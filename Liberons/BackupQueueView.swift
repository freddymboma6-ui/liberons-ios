import SwiftUI

struct BackupQueueView: View {
    @ObservedObject var backup: BackupEngine
    @ObservedObject var preferences: BackupPreferences
    @ObservedObject var analyzer: PhotoLibraryAnalyzer
    @ObservedObject var language: LanguageStore

    private var requestedCount: Int {
        max(1, preferences.selectedCount(total: analyzer.photoCount + analyzer.videoCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(language.text("Backup queue", "File de sauvegarde"), systemImage: "square.stack.3d.up.fill").font(.headline)
                Spacer()
                if backup.queueTotal > 0 { Text("\(backup.queueCompleted + backup.queueFailed)/\(backup.queueTotal)").font(.subheadline.bold()).monospacedDigit() }
            }

            if backup.queueTotal > 0 {
                ProgressView(value: backup.queueProgress).tint(.blue)
                HStack(spacing: 14) {
                    Label("\(backup.queueCompleted) " + language.text("protected", "protégés"), systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                    if backup.queueFailed > 0 { Label("\(backup.queueFailed) " + language.text("failed", "échoués"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }.font(.caption.bold())
                if let name = backup.currentQueueFilename { Text(language.text("Now: ", "En cours : ") + name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            } else {
                Text(language.text("Your selected percentage represents about \(requestedCount) photos or videos. Libérons will protect them one by one and verify each cloud copy.", "Votre pourcentage sélectionné représente environ \(requestedCount) photos ou vidéos. Libérons les protégera une par une et vérifiera chaque copie cloud.")).font(.subheadline).foregroundStyle(.secondary)
            }

            Button {
                Task { await backup.backupNewestItems(count: requestedCount) }
            } label: {
                HStack {
                    Spacer()
                    if backup.isRunning { ProgressView().tint(.white) }
                    Text(backup.isRunning ? language.text("Backup in progress…", "Sauvegarde en cours…") : language.text("Protect selected items", "Protéger les éléments sélectionnés")).fontWeight(.semibold)
                    Spacer()
                }.frame(height: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(backup.isRunning || !analyzer.canReadLibrary)

            Text(language.text("Nothing is deleted from this iPhone during backup.", "Rien n'est supprimé de cet iPhone pendant la sauvegarde.")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 18, y: 7)
    }
}
