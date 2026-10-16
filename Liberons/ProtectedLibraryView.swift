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
    @Namespace private var photoTransition
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

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
                                Text(isSelecting ? "\(selectedIDs.count) \(language.text("selected", "sélectionné(s)"))" : "\(store.items.count) \(language.text("items", "éléments"))")
                            }.font(.subheadline.bold()).foregroundStyle(.secondary).padding(.horizontal, 16)
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(store.items) { item in
                                    ProtectedLibraryTile(item: item)
                                        .matchedTransitionSource(id: item.id, in: photoTransition)
                                        .overlay(alignment: .topTrailing) {
                                            if isSelecting { Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(.white).padding(7) }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture { isSelecting ? toggle(item.id) : (viewerItem = item) }
                                        .onLongPressGesture(minimumDuration: 0.35) { if !isSelecting { isSelecting = true; selectedIDs = [item.id] } }
                                }
                            }
                        }.padding(.bottom, 100)
                    }.refreshable { await store.refresh() }
                }
            }
            .navigationTitle(isSelecting ? language.text("Select", "Sélection") : language.text("Library", "Bibliothèque"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.items.isEmpty { Button(isSelecting ? language.text("Done", "OK") : language.text("Select", "Sélectionner")) { isSelecting.toggle(); if !isSelecting { selectedIDs.removeAll() } } }
                }
                if isSelecting { ToolbarItemGroup(placement: .bottomBar) { Button(language.text("Select all", "Tout sélectionner")) { selectedIDs = Set(store.items.map(\.id)) }; Spacer(); Button(language.text("Delete", "Supprimer"), role: .destructive) { showBulkDelete = true }.disabled(selectedIDs.isEmpty || deletingSelection) } }
            }
            .task { await store.refresh() }
            .navigationDestination(item: $viewerItem) { item in
                ProtectedGalleryViewer(items: store.items, initialID: item.id, language: language).navigationTransition(.zoom(sourceID: item.id, in: photoTransition)).onDisappear { Task { await store.refresh() } }
            }
            .confirmationDialog(language.text("Delete selected memories from Libérons?", "Supprimer les souvenirs sélectionnés de Libérons ?"), isPresented: $showBulkDelete) {
                Button(language.text("Delete permanently", "Supprimer définitivement"), role: .destructive) { Task { await deleteSelected() } }
            }
        }
    }
    private func toggle(_ id: UUID) { if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) } }
    @MainActor private func deleteSelected() async { deletingSelection = true; for id in selectedIDs { try? await SupabaseService.deleteCloudMedia(assetID: id) }; selectedIDs.removeAll(); isSelecting = false; deletingSelection = false; await store.refresh() }
}

private struct ProtectedGalleryViewer: View {
    let items: [ProtectedCloudMedia]
    let initialID: UUID
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID
    @State private var showInfo = false
    @State private var verticalOffset: CGFloat = 0
    init(items: [ProtectedCloudMedia], initialID: UUID, language: LanguageStore) { self.items = items; self.initialID = initialID; self.language = language; _selection = State(initialValue: initialID) }
    private var current: ProtectedCloudMedia? { items.first { $0.id == selection } }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) { ForEach(items) { CloudPhotoPage(item: $0, language: language).tag($0.id) } }.tabViewStyle(.page(indexDisplayMode: .never)).ignoresSafeArea().offset(y: verticalOffset)
            VStack {
                HStack {
                    if let i = items.firstIndex(where: { $0.id == selection }) { Text("\(i + 1) / \(items.count)").font(.subheadline.bold()).foregroundStyle(.white).padding(8).background(.black.opacity(0.45), in: Capsule()) }
                    Spacer()
                    Button { showInfo = true } label: {
                        ZStack {
                            Color.clear
                            Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(.white)
                        }
                        .frame(width: 56, height: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.text("More options", "Plus d’options"))
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                Spacer()
            }
        }
        .gesture(DragGesture().onChanged { if $0.translation.height > abs($0.translation.width) { verticalOffset = max(0, $0.translation.height) } }.onEnded { value in if verticalOffset > 135 || value.predictedEndTranslation.height > 250 { dismiss() } else { withAnimation { verticalOffset = 0 } } })
        .toolbarBackground(.hidden, for: .navigationBar).toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showInfo) { if let current { ProtectedMediaDetail(item: current, language: language, closeViewer: { showInfo = false; dismiss() }) } }
    }
}

private struct CloudPhotoPage: View {
    let item: ProtectedCloudMedia
    @ObservedObject var language: LanguageStore
    @State private var image: UIImage?
    @State private var loading = true
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }
    var body: some View { ZStack { Color.black; if let image { Image(uiImage: image).resizable().scaledToFit() } else if loading { ProgressView().tint(.white) } else { Image(systemName: "exclamationmark.icloud").foregroundStyle(.white) }; if isVideo { Image(systemName: "play.circle.fill").font(.system(size: 68)).foregroundStyle(.white) } }.task(id: item.id) { await load() } }
    @MainActor private func load() async { guard !isVideo else { loading = false; return }; do { let url = try await SupabaseService.cloudMediaURL(assetID: item.id); let (data, _) = try await URLSession.shared.data(from: url); image = UIImage(data: data) } catch { }; loading = false }
}

private struct ProtectedMediaDetail: View {
    let item: ProtectedCloudMedia
    @ObservedObject var language: LanguageStore
    var closeViewer: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var operationError: String?
    @State private var deleting = false
    @State private var restoring = false
    @State private var localExists = false
    @State private var currentLocalIdentifier: String?
    @State private var restoredSuccessfully = false
    @State private var showDeviceDelete = false
    @State private var showCloudDelete = false
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text(item.originalFilename ?? (isVideo ? "Video" : "Photo")).font(.title3.bold()); Text(isVideo ? language.text("Video", "Vidéo") : "Photo").foregroundStyle(.secondary) }; Spacer(); Label(language.text("Protected", "Protégé"), systemImage: "checkmark.shield.fill").font(.caption.bold()).foregroundStyle(.green) }
                    Divider()
                    MetadataRow(icon: "calendar", title: language.text("Photo taken", "Photo prise le"), value: format(item.capturedAt))
                    MetadataRow(icon: "icloud.and.arrow.up", title: language.text("Added to Libérons", "Ajouté à Libérons le"), value: format(item.createdAt))
                    MetadataRow(icon: "checkmark.shield", title: language.text("Cloud protection verified", "Protection cloud vérifiée le"), value: format(item.protectedAt))
                    MetadataRow(icon: "externaldrive", title: language.text("Original size", "Taille originale"), value: ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                    MetadataRow(icon: "iphone", title: language.text("On this iPhone", "Sur cet iPhone"), value: localExists ? language.text("Available on this iPhone", "Disponible sur cet iPhone") : language.text("Not currently on this iPhone", "Pas actuellement sur cet iPhone"))
                    Label(language.text("Stored securely in Libérons Cloud.", "Stocké de manière sécurisée dans Libérons Cloud."), systemImage: "icloud.fill").font(.footnote).foregroundStyle(.secondary)
                    if restoredSuccessfully { Label(language.text("Restored to Photos", "Restauré dans Photos"), systemImage: "checkmark.circle.fill").font(.subheadline.bold()).foregroundStyle(.green).transition(.opacity.combined(with: .move(edge: .top))) }
                    Divider(); Text(language.text("Manage this memory", "Gérer ce souvenir")).font(.headline)
                    if !localExists && !isVideo { actionButton(language.text("Restore to Photos", "Restaurer dans Photos"), icon: "square.and.arrow.down", color: .blue) { Task { await restoreToPhotos() } }.disabled(restoring || deleting) }
                    if localExists { actionButton(language.text("Remove from this iPhone", "Supprimer de cet iPhone"), icon: "iphone.slash", color: .red) { showDeviceDelete = true } }
                    actionButton(language.text("Delete permanently from Libérons", "Supprimer définitivement de Libérons"), icon: "trash", color: .red) { showCloudDelete = true }.disabled(deleting || restoring)
                    if let operationError { Text(operationError).font(.footnote).foregroundStyle(.red) }
                }.padding(20)
            }
            .navigationTitle(language.text("Memory details", "Détails du souvenir")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(language.text("Done", "Fermer")) { dismiss() } } }
            .task { currentLocalIdentifier = item.iosLocalIdentifier; refreshLocalState() }
            .confirmationDialog(language.text("Remove from this iPhone?", "Supprimer de cet iPhone ?"), isPresented: $showDeviceDelete) { Button(language.text("Remove from iPhone", "Supprimer de l’iPhone"), role: .destructive) { Task { await removeFromDevice() } } }
            .confirmationDialog(language.text("Delete permanently from Libérons?", "Supprimer définitivement de Libérons ?"), isPresented: $showCloudDelete) { Button(language.text("Delete permanently", "Supprimer définitivement"), role: .destructive) { Task { await deleteFromCloud() } } }
        }
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View { Button(action: action) { HStack { if restoring && icon == "square.and.arrow.down" { ProgressView() }; Label(title, systemImage: icon) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(color) } }
    private func format(_ date: Date?) -> String { guard let date else { return language.text("Unknown", "Inconnue") }; return date.formatted(date: .long, time: .shortened) }

    private func matchingLocalAsset() -> PHAsset? {
        if let identifier = currentLocalIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject { return asset }
        let options = PHFetchOptions()
        if let capturedAt = item.capturedAt {
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", capturedAt.addingTimeInterval(-2) as NSDate, capturedAt.addingTimeInterval(2) as NSDate)
        }
        let result = PHAsset.fetchAssets(with: isVideo ? .video : .image, options: options)
        guard result.count > 0 else { return nil }
        if let filename = item.originalFilename {
            var match: PHAsset?
            result.enumerateObjects { asset, _, stop in
                if PHAssetResource.assetResources(for: asset).contains(where: { $0.originalFilename.caseInsensitiveCompare(filename) == .orderedSame }) {
                    match = asset; stop.pointee = true
                }
            }
            if let match { return match }
        }
        return result.firstObject
    }

    private func refreshLocalState() {
        if let asset = matchingLocalAsset() {
            currentLocalIdentifier = asset.localIdentifier
            localExists = true
        } else {
            localExists = false
        }
    }

    @MainActor private func restoreToPhotos() async {
        restoring = true; operationError = nil; restoredSuccessfully = false
        do {
            let url = try await SupabaseService.cloudMediaURL(assetID: item.id)
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), UIImage(data: data) != nil else { throw NSError(domain: "LiberonsRestore", code: 1, userInfo: [NSLocalizedDescriptionKey: language.text("Unable to restore this photo.", "Impossible de restaurer cette photo.")]) }
            var newIdentifier: String?
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = item.capturedAt
                let resourceOptions = PHAssetResourceCreationOptions()
                resourceOptions.originalFilename = item.originalFilename
                request.addResource(with: .photo, data: data, options: resourceOptions)
                newIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }
            guard let newIdentifier else { throw NSError(domain: "LiberonsRestore", code: 2, userInfo: [NSLocalizedDescriptionKey: language.text("Photos did not return the restored item identifier.", "Photos n’a pas retourné l’identifiant de l’élément restauré.")]) }
            currentLocalIdentifier = newIdentifier
            localExists = true
            restoredSuccessfully = true
            try? await SupabaseService.updateLocalIdentifier(assetID: item.id, localIdentifier: newIdentifier)
            for _ in 0..<12 {
                if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [newIdentifier], options: nil).firstObject {
                    currentLocalIdentifier = asset.localIdentifier
                    localExists = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        } catch {
            operationError = error.localizedDescription
            refreshLocalState()
        }
        restoring = false
    }

    @MainActor private func removeFromDevice() async {
        operationError = nil
        refreshLocalState()
        guard let asset = matchingLocalAsset() else {
            localExists = false
            operationError = language.text("This memory is no longer in Photos on this iPhone.", "Ce souvenir n’est plus présent dans Photos sur cet iPhone.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets([asset] as NSArray) }
            localExists = false
            restoredSuccessfully = false
            currentLocalIdentifier = nil
        } catch { operationError = error.localizedDescription }
    }
    @MainActor private func deleteFromCloud() async { deleting = true; operationError = nil; do { _ = try await SupabaseService.deleteCloudMedia(assetID: item.id); deleting = false; dismiss(); closeViewer?() } catch { deleting = false; operationError = error.localizedDescription } }
}

private struct MetadataRow: View {
    let icon: String; let title: String; let value: String
    var body: some View { HStack(alignment: .top, spacing: 13) { Image(systemName: icon).frame(width: 24).foregroundStyle(.blue); VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.bold()) }; Spacer() } }
}

private struct ProtectedLibraryTile: View {
    let item: ProtectedCloudMedia
    @State private var image: UIImage?
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }
    var body: some View { ZStack(alignment: .bottomTrailing) { GeometryReader { proxy in ZStack { Rectangle().fill(Color.secondary.opacity(0.10)); if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped() } else { Image(systemName: isVideo ? "video.fill" : "photo.fill").foregroundStyle(.secondary) } } }.aspectRatio(1, contentMode: .fit); Image(systemName: "checkmark.shield.fill").font(.caption).foregroundStyle(.white).padding(6).background(.green, in: Circle()).padding(7) }.task(id: item.id) { await loadThumbnail() } }
    @MainActor private func loadThumbnail() async { if let identifier = item.iosLocalIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject { let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 500, height: 500), contentMode: .aspectFill, options: options) { value, _ in if let value { Task { @MainActor in image = value } } }; return }; guard !isVideo else { return }; do { let url = try await SupabaseService.cloudMediaURL(assetID: item.id); let (data, _) = try await URLSession.shared.data(from: url); image = UIImage(data: data) } catch { } }
}