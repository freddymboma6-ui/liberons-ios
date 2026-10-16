import SwiftUI

struct FreeSpaceView: View {
    @ObservedObject var preferences: BackupPreferences
    @ObservedObject var language: LanguageStore
    @StateObject private var cleaner = ProtectedSpaceCleaner()
    @State private var showReview = false

    private var selectedSize: String { ByteCountFormatter.string(fromByteCount: cleaner.selectedBytes, countStyle: .file) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(language.text("Free protected space", "Libérer l’espace protégé"), systemImage: "iphone.and.arrow.forward").font(.headline)
                Spacer()
                Text("\(preferences.removalPercent)%").font(.headline).foregroundStyle(.green)
            }
            Text(language.text("The percentage only prepares a selection. Nothing is removed when you tap a percentage.", "Le pourcentage prépare uniquement une sélection. Rien n’est supprimé lorsque vous touchez un pourcentage.")).font(.subheadline).foregroundStyle(.secondary)

            NavigationLink {
                StorageAnalysisView(language: language)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.blue.opacity(0.11)).frame(width: 44, height: 44)
                        Image(systemName: "chart.bar.doc.horizontal.fill").foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("Analyze iPhone storage", "Analyser le stockage de l’iPhone")).fontWeight(.semibold).foregroundStyle(.primary)
                        Text(language.text("Find screenshots, 4K videos and your largest files", "Trouvez les captures, vidéos 4K et vos fichiers les plus lourds")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(LiberonsTheme.insetCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if cleaner.isLoading {
                ProgressView(language.text("Calculating what can be freed…", "Calcul de l’espace réellement libérable…"))
            } else if cleaner.selectedLocalIdentifiers.isEmpty {
                Text(language.text("Continue to calculate which protected and verified originals are still on this iPhone.", "Continuez pour calculer quels originaux protégés et vérifiés sont encore présents sur cet iPhone.")).font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(cleaner.selectedLocalIdentifiers.count) " + language.text("item(s)", "élément(s)")).font(.title3.bold())
                    Text(language.text("About \(selectedSize) can be freed", "Environ \(selectedSize) peuvent être libérés")).foregroundStyle(.green).fontWeight(.semibold)
                }
            }

            if !cleaner.message.isEmpty {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                    Text(cleaner.message).font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LiberonsTheme.insetCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                Task {
                    await cleaner.prepare(removalPercent: preferences.removalPercent)
                    if !cleaner.selectedLocalIdentifiers.isEmpty { showReview = true }
                }
            } label: {
                HStack { Spacer(); if cleaner.isLoading { ProgressView() }; Label(language.text("Continue", "Continuer"), systemImage: "arrow.right.circle.fill"); Spacer() }.frame(height: 34)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(cleaner.isLoading || cleaner.isDeleting)

            Label(language.text("Libérons never deletes the cloud copy here. Apple Photos asks for its own confirmation before removing local originals.", "Libérons ne supprime jamais la copie cloud ici. Photos demande sa propre confirmation avant de retirer les originaux locaux."), systemImage: "lock.shield.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 18, y: 7)
        .sheet(isPresented: $showReview) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 22) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.green.opacity(0.12)).frame(width: 72, height: 72)
                        Image(systemName: "iphone.and.arrow.forward").font(.system(size: 31, weight: .semibold)).foregroundStyle(.green)
                    }
                    Text(language.text("Ready to free space", "Prêt à libérer de l’espace")).font(.largeTitle.bold())
                    Text(language.text("Review your selection before anything is removed from this iPhone.", "Vérifiez votre sélection avant que quoi que ce soit soit retiré de cet iPhone.")).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        reviewRow(language.text("Selected", "Sélection"), "\(cleaner.selectedLocalIdentifiers.count) " + language.text("items", "élément(s)"))
                        Divider()
                        reviewRow(language.text("Space to free", "Espace à libérer"), selectedSize)
                        Divider()
                        reviewRow(language.text("Cloud copies", "Copies cloud"), language.text("Remain protected", "Restent protégées"))
                    }
                    .padding(.horizontal, 18)
                    .background(LiberonsTheme.insetCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Label(language.text("Photos will display the final iOS confirmation. If you cancel there, nothing changes.", "Photos affichera ensuite la confirmation finale d’iOS. Si vous refusez, rien ne change."), systemImage: "checkmark.shield.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        showReview = false
                        Task { await cleaner.deletePreparedFromIPhone() }
                    } label: {
                        Text(language.text("Free \(selectedSize)", "Libérer \(selectedSize)")).fontWeight(.bold).frame(maxWidth: .infinity).frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(cleaner.isDeleting)
                    Button(language.text("Cancel", "Annuler")) { showReview = false }.frame(maxWidth: .infinity)
                }
                .padding(24)
                .navigationTitle(language.text("Review", "Récapitulatif"))
                .navigationBarTitleDisplayMode(.inline)
                .background(LiberonsTheme.canvas)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing) }.padding(.vertical, 15)
    }
}
