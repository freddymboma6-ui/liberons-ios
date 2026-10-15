import SwiftUI

struct FreeSpaceView: View {
    @ObservedObject var preferences: BackupPreferences
    @ObservedObject var language: LanguageStore
    @StateObject private var cleaner = ProtectedSpaceCleaner()
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(language.text("Free protected space", "Libérer l’espace protégé"), systemImage: "iphone.and.arrow.forward").font(.headline)
                Spacer()
                Text("\(preferences.removalPercent)%").font(.headline).foregroundStyle(.green)
            }

            if cleaner.isLoading {
                ProgressView(language.text("Checking protected originals…", "Vérification des originaux protégés…"))
            } else if cleaner.selectedLocalIdentifiers.isEmpty {
                Text(language.text("First check which protected originals can safely leave this iPhone.", "Vérifiez d’abord quels originaux protégés peuvent quitter cet iPhone en toute sécurité.")).font(.subheadline).foregroundStyle(.secondary)
            } else {
                Label("\(cleaner.selectedLocalIdentifiers.count) " + language.text("protected originals selected", "originaux protégés sélectionnés"), systemImage: "checkmark.shield.fill").foregroundStyle(.green).font(.subheadline.bold())
                Text(language.text("Only items already marked Protected in Libérons Cloud are included. The oldest protected originals are selected first.", "Seuls les éléments déjà marqués Protégé dans Libérons Cloud sont inclus. Les originaux protégés les plus anciens sont sélectionnés en premier.")).font(.caption).foregroundStyle(.secondary)
            }

            if !cleaner.message.isEmpty { Text(cleaner.message).font(.caption).foregroundStyle(.secondary) }

            Button {
                Task { await cleaner.prepare(removalPercent: preferences.removalPercent) }
            } label: {
                Label(language.text("Check protected originals", "Vérifier les originaux protégés"), systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity).frame(height: 34)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(cleaner.isLoading || cleaner.isDeleting)

            if !cleaner.selectedLocalIdentifiers.isEmpty {
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    HStack { Spacer(); if cleaner.isDeleting { ProgressView() }; Text(language.text("Free space on this iPhone", "Libérer l’espace sur cet iPhone")).fontWeight(.semibold); Spacer() }.frame(height: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(cleaner.isDeleting)
            }

            Label(language.text("Cloud copies are kept. iOS will ask for system confirmation before local Photos originals are removed.", "Les copies cloud sont conservées. iOS demandera une confirmation système avant de retirer les originaux de Photos sur cet iPhone."), systemImage: "lock.shield.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 18, y: 7)
        .confirmationDialog(language.text("Remove local originals?", "Retirer les originaux locaux ?"), isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(language.text("Continue to iOS confirmation", "Continuer vers la confirmation iOS"), role: .destructive) {
                Task { await cleaner.deletePreparedFromIPhone() }
            }
            Button(language.text("Cancel", "Annuler"), role: .cancel) {}
        } message: {
            Text(language.text("Only verified protected items are included. Their Libérons Cloud copies remain protected.", "Seuls les éléments protégés et vérifiés sont inclus. Leurs copies Libérons Cloud restent protégées."))
        }
    }
}
