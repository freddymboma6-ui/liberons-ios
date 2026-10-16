import SwiftUI
import Photos

struct ProtectedLibraryView: View {
    @ObservedObject var language: LanguageStore
    @StateObject private var store = ProtectedMediaStore()
    @State private var selected: ProtectedCloudMedia?
    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.items.isEmpty { ProgressView(language.text("Loading your library…", "Chargement de votre bibliothèque…")) }
                else if let error = store.errorMessage, store.items.isEmpty { ContentUnavailableView { Label(language.text("Library unavailable", "Bibliothèque indisponible"), systemImage: "exclamationmark.icloud") } description: { Text(error) } actions: { Button(language.text("Try again", "Réessayer")) { Task { await store.refresh() } } } }
                else if store.items.isEmpty { ContentUnavailableView(language.text("Your cloud library", "Votre bibliothèque cloud"), systemImage: "photo.stack", description: Text(language.text("Protected memories will appear here.", "Vos souvenirs protégés apparaîtront ici."))) }
                else { ScrollView { VStack(alignment: .leading, spacing: 12) { HStack { Label(language.text("Protected", "Protégés"), systemImage: "checkmark.shield.fill").foregroundStyle(.green); Spacer(); Text("\(store.items.count) \(language.text("items", "éléments"))").foregroundStyle(.secondary) }.font(.subheadline.bold()).padding(.horizontal, 16); LazyVGrid(columns: columns, spacing: 2) { ForEach(store.items) { item in Button { selected = item } label: { ProtectedLibraryTile(item: item) }.buttonStyle(.plain) } } }.padding(.bottom, 100) }.refreshable { await store.refresh() } }
            }
            .navigationTitle(language.text("Library", "Bibliothèque"))
            .task { await store.refresh() }
            .sheet(item: $selected, onDismiss: { Task { await store.refresh() } }) { item in ProtectedMediaDetail(item: item, language: language) }
        }
    }
}

private struct ProtectedMediaDetail: View {
    let item: ProtectedCloudMedia
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var operationError: String?
    @State private var deleting = false
    @State private var showDeviceDelete = false
    @State private var showCloudDelete = false
    @State private var localExists = false
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ZStack {
                        Rectangle().fill(.black)
                        if let image { Image(uiImage: image).resizable().scaledToFit() }
                        else if let errorMessage { VStack(spacing: 12) { Image(systemName: "exclamationmark.icloud").font(.largeTitle); Text(errorMessage).font(.caption).multilineTextAlignment(.center); Button(language.text("Try again", "Réessayer")) { Task { await loadFromCloud() } } }.foregroundStyle(.white).padding() }
                        else if loading { ProgressView().tint(.white) }
                        if isVideo { Image(systemName: "play.circle.fill").font(.system(size: 64)).foregroundStyle(.white).shadow(radius: 10) }
                    }.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)

                    VStack(alignment: .leading, spacing: 18) {
                        HStack { VStack(alignment: .leading, spacing: 4) { Text(item.originalFilename ?? (isVideo ? "Video" : "Photo")).font(.title3.bold()); Text(isVideo ? language.text("Video", "Vidéo") : "Photo").foregroundStyle(.secondary) }; Spacer(); Label(language.text("Protected", "Protégé"), systemImage: "checkmark.shield.fill").font(.caption.bold()).foregroundStyle(.green) }
                        Divider()
                        MetadataRow(icon: "calendar", title: language.text("Photo taken", "Photo prise le"), value: format(item.capturedAt))
                        MetadataRow(icon: "icloud.and.arrow.up", title: language.text("Added to Libérons", "Ajouté à Libérons le"), value: format(item.createdAt))
                        MetadataRow(icon: "checkmark.shield", title: language.text("Cloud protection verified", "Protection cloud vérifiée le"), value: format(item.protectedAt))
                        MetadataRow(icon: "externaldrive", title: language.text("Original size", "Taille originale"), value: ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                        MetadataRow(icon: "iphone", title: language.text("On this iPhone", "Sur cet iPhone"), value: localExists ? language.text("Original still on device", "Original encore sur l’appareil") : language.text("No local original found", "Aucun original local trouvé"))
                        Label(language.text("Loaded securely from Libérons Cloud.", "Chargé de manière sécurisée depuis Libérons Cloud."), systemImage: "icloud.fill").font(.footnote).foregroundStyle(.secondary)

                        Divider().padding(.vertical, 2)
                        Text(language.text("Manage this memory", "Gérer ce souvenir")).font(.headline)

                        if localExists {
                            Button(role: .destructive) { showDeviceDelete = true } label: {
                                Label(language.text("Remove from this iPhone", "Supprimer de cet iPhone"), systemImage: "iphone.slash")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                            }
                            Text(language.text("The protected Libérons Cloud copy stays available.", "La copie protégée dans Libérons Cloud reste disponible.")).font(.caption).foregroundStyle(.secondary)
                        }

                        Button(role: .destructive) { showCloudDelete = true } label: {
                            Label(language.text("Delete permanently from Libérons", "Supprimer définitivement de Libérons"), systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        }.disabled(deleting)

                        if deleting { HStack { Spacer(); ProgressView(); Text(language.text("Deleting…", "Suppression…")); Spacer() }.font(.footnote).foregroundStyle(.secondary) }
                        if let operationError { Text(operationError).font(.footnote).foregroundStyle(.red) }
                    }.padding(20)
                }
            }
            .ignoresSafeArea(edges: .top)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(language.text("Done", "Fermer")) { dismiss() } } }
            .task { refreshLocalState(); await loadFromCloud() }
            .confirmationDialog(language.text("Remove from this iPhone?", "Supprimer de cet iPhone ?"), isPresented: $showDeviceDelete, titleVisibility: .visible) {
                Button(language.text("Remove from iPhone", "Supprimer de l’iPhone"), role: .destructive) { Task { await removeFromDevice() } }
                Button(language.text("Cancel", "Annuler"), role: .cancel) { }
            } message: { Text(language.text("The verified Libérons Cloud copy will be kept. Apple will ask you to confirm the Photos deletion.", "La copie vérifiée dans Libérons Cloud sera conservée. Apple vous demandera de confirmer la suppression dans Photos.")) }
            .confirmationDialog(language.text("Delete permanently from Libérons?", "Supprimer définitivement de Libérons ?"), isPresented: $showCloudDelete, titleVisibility: .visible) {
                Button(language.text("Delete permanently", "Supprimer définitivement"), role: .destructive) { Task { await deleteFromCloud() } }
                Button(language.text("Cancel", "Annuler"), role: .cancel) { }
            } message: {
                Text(localExists
                     ? language.text("The cloud copy will be permanently deleted and its storage will be released. The original currently remains on this iPhone.", "La copie cloud sera supprimée définitivement et son espace sera libéré. L’original est actuellement encore sur cet iPhone.")
                     : language.text("Warning: no local original was found on this iPhone. Deleting this Libérons copy may permanently remove your last available copy.", "Attention : aucun original local n’a été trouvé sur cet iPhone. Supprimer cette copie Libérons peut supprimer définitivement votre dernière copie disponible."))
            }
        }
    }

    private func format(_ date: Date?) -> String { guard let date else { return language.text("Unknown", "Inconnue") }; return date.formatted(date: .long, time: .shortened) }
    private func refreshLocalState() { guard let identifier = item.iosLocalIdentifier else { localExists = false; return }; localExists = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject != nil }

    @MainActor private func loadFromCloud() async {
        loading = true; errorMessage = nil; image = nil
        do {
            let url = try await SupabaseService.cloudMediaURL(assetID: item.id)
            if isVideo { errorMessage = language.text("Cloud video playback is coming next.", "La lecture des vidéos cloud arrive ensuite."); loading = false; return }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let decoded = UIImage(data: data) else { throw NSError(domain: "LiberonsCloud", code: -3, userInfo: [NSLocalizedDescriptionKey: language.text("Unable to decode this cloud photo.", "Impossible de décoder cette photo cloud.")]) }
            image = decoded; loading = false
        } catch { errorMessage = error.localizedDescription; loading = false }
    }

    @MainActor private func removeFromDevice() async {
        operationError = nil
        guard let identifier = item.iosLocalIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { refreshLocalState(); return }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets([asset] as NSArray) }
            refreshLocalState()
        } catch { operationError = error.localizedDescription }
    }

    @MainActor private func deleteFromCloud() async {
        deleting = true; operationError = nil
        do {
            _ = try await SupabaseService.deleteCloudMedia(assetID: item.id)
            deleting = false
            dismiss()
        } catch { deleting = false; operationError = error.localizedDescription }
    }
}

private struct MetadataRow: View { let icon: String; let title: String; let value: String; var body: some View { HStack(alignment: .top, spacing: 13) { Image(systemName: icon).frame(width: 24).foregroundStyle(.blue); VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.bold()) }; Spacer() } } }

private struct ProtectedLibraryTile: View {
    let item: ProtectedCloudMedia
    @State private var image: UIImage?
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }
    var body: some View { ZStack(alignment: .bottomTrailing) { GeometryReader { proxy in ZStack { Rectangle().fill(Color.secondary.opacity(0.10)); if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped() } else { Image(systemName: isVideo ? "video.fill" : "photo.fill").font(.title2).foregroundStyle(.secondary) } } }.aspectRatio(1, contentMode: .fit); if isVideo { Image(systemName: "play.fill").font(.caption.bold()).foregroundStyle(.white).padding(7).background(.black.opacity(0.55), in: Circle()).padding(7) }; Image(systemName: "checkmark.shield.fill").font(.caption).foregroundStyle(.white).padding(6).background(.green.opacity(0.9), in: Circle()).padding(7).offset(x: isVideo ? -34 : 0) }.task(id: item.id) { await loadThumbnail() }.accessibilityLabel(item.originalFilename ?? (isVideo ? "Video" : "Photo")) }
    @MainActor private func loadThumbnail() async {
        if let identifier = item.iosLocalIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
            let options = PHImageRequestOptions(); options.deliveryMode = .opportunistic; options.resizeMode = .fast; options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 500, height: 500), contentMode: .aspectFill, options: options) { value, _ in if let value { Task { @MainActor in image = value } } }
            return
        }
        guard !isVideo else { return }
        do { let url = try await SupabaseService.cloudMediaURL(assetID: item.id); let (data, _) = try await URLSession.shared.data(from: url); image = UIImage(data: data) } catch { }
    }
}
