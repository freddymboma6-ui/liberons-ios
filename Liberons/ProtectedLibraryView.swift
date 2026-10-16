import SwiftUI
import Photos

struct ProtectedLibraryView: View {
    @ObservedObject var language: LanguageStore
    @StateObject private var store = ProtectedMediaStore()
    @State private var viewerItem: ProtectedCloudMedia?
    @State private var selectedIDs: Set<UUID> = []
    @State private var isSelecting = false
    @State private var showBulkDelete = false
    @State private var deletingSelection = false
    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.items.isEmpty {
                    ProgressView(language.text("Loading your library…", "Chargement de votre bibliothèque…"))
                } else if let error = store.errorMessage, store.items.isEmpty {
                    ContentUnavailableView { Label(language.text("Library unavailable", "Bibliothèque indisponible"), systemImage: "exclamationmark.icloud") } description: { Text(error) } actions: { Button(language.text("Try again", "Réessayer")) { Task { await store.refresh() } } }
                } else if store.items.isEmpty {
                    ContentUnavailableView(language.text("Your cloud library", "Votre bibliothèque cloud"), systemImage: "photo.stack", description: Text(language.text("Protected memories will appear here.", "Vos souvenirs protégés apparaîtront ici.")))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(language.text("Protected", "Protégés"), systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                                Spacer()
                                if isSelecting { Text("\(selectedIDs.count) \(language.text("selected", "sélectionné(s)"))") } else { Text("\(store.items.count) \(language.text("items", "éléments"))") }
                            }.font(.subheadline.bold()).foregroundStyle(.secondary).padding(.horizontal, 16)

                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(store.items) { item in
                                    ProtectedLibraryTile(item: item)
                                        .overlay(alignment: .topTrailing) {
                                            if isSelecting {
                                                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.title2).symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, selectedIDs.contains(item.id) ? Color.blue : Color.black.opacity(0.35))
                                                    .padding(7)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if isSelecting { toggle(item.id) } else { viewerItem = item }
                                        }
                                        .onLongPressGesture(minimumDuration: 0.35) {
                                            if !isSelecting { isSelecting = true; selectedIDs = [item.id] }
                                        }
                                        .simultaneousGesture(
                                            DragGesture(minimumDistance: 8)
                                                .onChanged { _ in
                                                    guard isSelecting else { return }
                                                    selectedIDs.insert(item.id)
                                                }
                                        )
                                        .contextMenu {
                                            Button { viewerItem = item } label: { Label(language.text("View", "Afficher"), systemImage: "photo") }
                                            Button { isSelecting = true; selectedIDs = [item.id] } label: { Label(language.text("Select", "Sélectionner"), systemImage: "checkmark.circle") }
                                            Divider()
                                            Button(role: .destructive) { selectedIDs = [item.id]; showBulkDelete = true } label: { Label(language.text("Delete from Libérons", "Supprimer de Libérons"), systemImage: "trash") }
                                        }
                                }
                            }
                        }.padding(.bottom, 100)
                    }.refreshable { await store.refresh() }
                }
            }
            .navigationTitle(isSelecting ? language.text("Select", "Sélection") : language.text("Library", "Bibliothèque"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.items.isEmpty {
                        Button(isSelecting ? language.text("Done", "OK") : language.text("Select", "Sélectionner")) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isSelecting.toggle()
                                if !isSelecting { selectedIDs.removeAll() }
                            }
                        }
                    }
                }
                if isSelecting {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { selectedIDs = Set(store.items.map(\.id)) } label: { Label(language.text("Select all", "Tout sélectionner"), systemImage: "checkmark.circle") }
                        Spacer()
                        Button(role: .destructive) { showBulkDelete = true } label: { if deletingSelection { ProgressView() } else { Label(language.text("Delete", "Supprimer"), systemImage: "trash") } }.disabled(selectedIDs.isEmpty || deletingSelection)
                    }
                }
            }
            .task { await store.refresh() }
            .navigationDestination(item: $viewerItem) { item in
                ProtectedGalleryViewer(items: store.items, initialID: item.id, language: language)
                    .onDisappear { Task { await store.refresh() } }
            }
            .confirmationDialog(language.text("Delete selected memories from Libérons?", "Supprimer les souvenirs sélectionnés de Libérons ?"), isPresented: $showBulkDelete, titleVisibility: .visible) {
                Button(language.text("Delete permanently", "Supprimer définitivement"), role: .destructive) { Task { await deleteSelected() } }
                Button(language.text("Cancel", "Annuler"), role: .cancel) { }
            } message: { Text(language.text("The selected cloud copies will be permanently deleted. This cannot be undone.", "Les copies cloud sélectionnées seront supprimées définitivement. Cette action est irréversible.")) }
        }
    }

    private func toggle(_ id: UUID) { if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) } }

    @MainActor private func deleteSelected() async {
        deletingSelection = true
        for id in selectedIDs { do { _ = try await SupabaseService.deleteCloudMedia(assetID: id) } catch { } }
        selectedIDs.removeAll(); isSelecting = false; deletingSelection = false
        await store.refresh()
    }
}

private struct ProtectedGalleryViewer: View {
    let items: [ProtectedCloudMedia]
    let initialID: UUID
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID
    @State private var showInfo = false

    init(items: [ProtectedCloudMedia], initialID: UUID, language: LanguageStore) { self.items = items; self.initialID = initialID; self.language = language; _selection = State(initialValue: initialID) }
    private var current: ProtectedCloudMedia? { items.first(where: { $0.id == selection }) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) { ForEach(items) { item in CloudPhotoPage(item: item, language: language).tag(item.id) } }.tabViewStyle(.page(indexDisplayMode: .never)).ignoresSafeArea()
            VStack {
                HStack {
                    if let index = items.firstIndex(where: { $0.id == selection }) { Text("\(index + 1) / \(items.count)").font(.subheadline.bold()).foregroundStyle(.white).padding(.horizontal, 13).padding(.vertical, 8).background(.black.opacity(0.45), in: Capsule()) }
                    Spacer()
                    Button { showInfo = true } label: { Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(.white).frame(width: 42, height: 42).background(.black.opacity(0.45), in: Circle()) }
                }.padding(.horizontal, 16).padding(.top, 8)
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showInfo) { if let current { ProtectedMediaDetail(item: current, language: language, closeViewer: { showInfo = false; dismiss() }) } }
    }
}

private struct CloudPhotoPage: View {
    let item: ProtectedCloudMedia
    @ObservedObject var language: LanguageStore
    @State private var image: UIImage?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var scale: CGFloat = 1
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }
    var body: some View {
        GeometryReader { proxy in ZStack { Color.black; if let image { Image(uiImage: image).resizable().scaledToFit().scaleEffect(scale).gesture(MagnificationGesture().onChanged { scale = max(1, $0) }.onEnded { if $0 < 1.05 { scale = 1 } }) } else if loading { ProgressView().tint(.white) } else { VStack(spacing: 12) { Image(systemName: "exclamationmark.icloud").font(.largeTitle); Text(errorMessage ?? language.text("Unable to load this memory.", "Impossible de charger ce souvenir.")).font(.caption).multilineTextAlignment(.center); Button(language.text("Try again", "Réessayer")) { Task { await load() } } }.foregroundStyle(.white).padding() }; if isVideo { Image(systemName: "play.circle.fill").font(.system(size: 68)).foregroundStyle(.white) } }.frame(width: proxy.size.width, height: proxy.size.height) }.task(id: item.id) { await load() }
    }
    @MainActor private func load() async { loading = true; errorMessage = nil; image = nil; do { guard !isVideo else { throw NSError(domain: "LiberonsCloud", code: -8, userInfo: [NSLocalizedDescriptionKey: language.text("Cloud video playback is coming next.", "La lecture vidéo cloud arrive ensuite.")]) }; let url = try await SupabaseService.cloudMediaURL(assetID: item.id); let (data, response) = try await URLSession.shared.data(from: url); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let decoded = UIImage(data: data) else { throw NSError(domain: "LiberonsCloud", code: -3, userInfo: [NSLocalizedDescriptionKey: language.text("Unable to decode this cloud photo.", "Impossible de décoder cette photo cloud.")]) }; image = decoded; loading = false } catch { errorMessage = error.localizedDescription; loading = false } }
}

private struct ProtectedMediaDetail: View {
    let item: ProtectedCloudMedia
    @ObservedObject var language: LanguageStore
    var closeViewer: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var operationError: String?
    @State private var deleting = false
    @State private var restoring = false
    @State private var showDeviceDelete = false
    @State private var showCloudDelete = false
    @State private var localExists = false
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }

    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading, spacing: 4) { Text(item.originalFilename ?? (isVideo ? "Video" : "Photo")).font(.title3.bold()); Text(isVideo ? language.text("Video", "Vidéo") : "Photo").foregroundStyle(.secondary) }; Spacer(); Label(language.text("Protected", "Protégé"), systemImage: "checkmark.shield.fill").font(.caption.bold()).foregroundStyle(.green) }
            Divider(); MetadataRow(icon: "calendar", title: language.text("Photo taken", "Photo prise le"), value: format(item.capturedAt)); MetadataRow(icon: "icloud.and.arrow.up", title: language.text("Added to Libérons", "Ajouté à Libérons le"), value: format(item.createdAt)); MetadataRow(icon: "checkmark.shield", title: language.text("Cloud protection verified", "Protection cloud vérifiée le"), value: format(item.protectedAt)); MetadataRow(icon: "externaldrive", title: language.text("Original size", "Taille originale"), value: ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file)); MetadataRow(icon: "iphone", title: language.text("On this iPhone", "Sur cet iPhone"), value: localExists ? language.text("Original still on device", "Original encore sur l’appareil") : language.text("No local original found", "Aucun original local trouvé")); Label(language.text("Stored securely in Libérons Cloud.", "Stocké de manière sécurisée dans Libérons Cloud."), systemImage: "icloud.fill").font(.footnote).foregroundStyle(.secondary)
            Divider(); Text(language.text("Manage this memory", "Gérer ce souvenir")).font(.headline)
            if !localExists && !isVideo { Button { Task { await restoreToPhotos() } } label: { HStack { if restoring { ProgressView() }; Label(language.text("Restore to Photos", "Restaurer dans Photos"), systemImage: "square.and.arrow.down") }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 14)) }.disabled(restoring || deleting) }
            if localExists { Button(role: .destructive) { showDeviceDelete = true } label: { Label(language.text("Remove from this iPhone", "Supprimer de cet iPhone"), systemImage: "iphone.slash").frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14)) }; Text(language.text("The protected Libérons Cloud copy stays available.", "La copie protégée dans Libérons Cloud reste disponible.")).font(.caption).foregroundStyle(.secondary) }
            Button(role: .destructive) { showCloudDelete = true } label: { Label(language.text("Delete permanently from Libérons", "Supprimer définitivement de Libérons"), systemImage: "trash").frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)) }.disabled(deleting || restoring)
            if let operationError { Text(operationError).font(.footnote).foregroundStyle(.red) }
        }.padding(20) } .navigationTitle(language.text("Memory details", "Détails du souvenir")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(language.text("Done", "Fermer")) { dismiss() } } }
        .task { refreshLocalState() }
        .confirmationDialog(language.text("Remove from this iPhone?", "Supprimer de cet iPhone ?"), isPresented: $showDeviceDelete, titleVisibility: .visible) { Button(language.text("Remove from iPhone", "Supprimer de l’iPhone"), role: .destructive) { Task { await removeFromDevice() } }; Button(language.text("Cancel", "Annuler"), role: .cancel) { } } message: { Text(language.text("The verified Libérons Cloud copy will be kept. Apple will ask you to confirm the Photos deletion.", "La copie vérifiée dans Libérons Cloud sera conservée. Apple vous demandera de confirmer la suppression dans Photos.")) }
        .confirmationDialog(language.text("Delete permanently from Libérons?", "Supprimer définitivement de Libérons ?"), isPresented: $showCloudDelete, titleVisibility: .visible) { Button(language.text("Delete permanently", "Supprimer définitivement"), role: .destructive) { Task { await deleteFromCloud() } }; Button(language.text("Cancel", "Annuler"), role: .cancel) { } } message: { Text(localExists ? language.text("The cloud copy will be permanently deleted. The original remains on this iPhone.", "La copie cloud sera supprimée définitivement. L’original reste sur cet iPhone.") : language.text("Warning: no local original was found. This may permanently remove your last available copy.", "Attention : aucun original local n’a été trouvé. Cela peut supprimer définitivement votre dernière copie disponible.")) }
        }
    }

    private func format(_ date: Date?) -> String { guard let date else { return language.text("Unknown", "Inconnue") }; return date.formatted(date: .long, time: .shortened) }
    private func refreshLocalState() { guard let identifier = item.iosLocalIdentifier else { localExists = false; return }; localExists = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject != nil }

    @MainActor private func restoreToPhotos() async {
        restoring = true; operationError = nil
        do {
            let url = try await SupabaseService.cloudMediaURL(assetID: item.id); let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), UIImage(data: data) != nil else { throw NSError(domain: "LiberonsRestore", code: 1, userInfo: [NSLocalizedDescriptionKey: language.text("Unable to download the original photo.", "Impossible de télécharger la photo originale.")]) }
            try await PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil) }
            localExists = true; restoring = false
        } catch { restoring = false; operationError = error.localizedDescription }
    }

    @MainActor private func removeFromDevice() async { operationError = nil; guard let identifier = item.iosLocalIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { refreshLocalState(); return }; do { try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets([asset] as NSArray) }; refreshLocalState() } catch { operationError = error.localizedDescription } }
    @MainActor private func deleteFromCloud() async { deleting = true; operationError = nil; do { _ = try await SupabaseService.deleteCloudMedia(assetID: item.id); deleting = false; dismiss(); closeViewer?() } catch { deleting = false; operationError = error.localizedDescription } }
}

private struct MetadataRow: View { let icon: String; let title: String; let value: String; var body: some View { HStack(alignment: .top, spacing: 13) { Image(systemName: icon).frame(width: 24).foregroundStyle(.blue); VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.bold()) }; Spacer() } } }

private struct ProtectedLibraryTile: View {
    let item: ProtectedCloudMedia; @State private var image: UIImage?; private var isVideo: Bool { item.mediaType.lowercased().contains("video") }
    var body: some View { ZStack(alignment: .bottomTrailing) { GeometryReader { proxy in ZStack { Rectangle().fill(Color.secondary.opacity(0.10)); if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped() } else { Image(systemName: isVideo ? "video.fill" : "photo.fill").font(.title2).foregroundStyle(.secondary) } } }.aspectRatio(1, contentMode: .fit); if isVideo { Image(systemName: "play.fill").font(.caption.bold()).foregroundStyle(.white).padding(7).background(.black.opacity(0.55), in: Circle()).padding(7) }; Image(systemName: "checkmark.shield.fill").font(.caption).foregroundStyle(.white).padding(6).background(.green.opacity(0.9), in: Circle()).padding(7).offset(x: isVideo ? -34 : 0) }.task(id: item.id) { await loadThumbnail() } }
    @MainActor private func loadThumbnail() async { if let identifier = item.iosLocalIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject { let options = PHImageRequestOptions(); options.deliveryMode = .opportunistic; options.resizeMode = .fast; options.isNetworkAccessAllowed = true; PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 500, height: 500), contentMode: .aspectFill, options: options) { value, _ in if let value { Task { @MainActor in image = value } } }; return }; guard !isVideo else { return }; do { let url = try await SupabaseService.cloudMediaURL(assetID: item.id); let (data, _) = try await URLSession.shared.data(from: url); image = UIImage(data: data) } catch { } }
}
