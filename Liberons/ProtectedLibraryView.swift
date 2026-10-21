import SwiftUI
import Photos
import AVKit
import AVFoundation

private enum ProtectedLibraryFilter: String, CaseIterable, Identifiable {
    case all, photos, videos
    var id: String { rawValue }
    var icon: String { self == .all ? "square.grid.2x2.fill" : (self == .photos ? "photo.fill" : "play.rectangle.fill") }
    func title(_ language: LanguageStore) -> String { self == .all ? language.text("All", "Tout") : (self == .photos ? "Photos" : language.text("Videos", "Vidéos")) }
}

struct ProtectedLibraryView: View {
    @ObservedObject var language: LanguageStore
    @StateObject private var store = ProtectedMediaStore()
    @StateObject private var billing = CloudStorageSummary()
    @State private var viewerItem: ProtectedCloudMedia?
    @State private var selectedIDs: Set<UUID> = []
    @State private var isSelecting = false
    @State private var showBulkDelete = false
    @State private var deletingSelection = false
    @State private var mediaFilter: ProtectedLibraryFilter = .all
    @State private var sortNewestFirst = true
    @State private var displayItems: [ProtectedCloudMedia] = []
    @State private var filterCounts: [ProtectedLibraryFilter: Int] = [:]
    @Namespace private var photoTransition
    @Namespace private var filterTransition
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 3)
    private func isVideo(_ item: ProtectedCloudMedia) -> Bool { item.mediaType.lowercased().contains("video") }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.items.isEmpty { ProgressView(language.text("Loading your library…", "Chargement de votre bibliothèque…")) }
                else if let error = store.errorMessage, store.items.isEmpty { ContentUnavailableView { Label(language.text("Library unavailable", "Bibliothèque indisponible"), systemImage: "exclamationmark.icloud") } description: { Text(error) } actions: { Button(language.text("Try again", "Réessayer")) { Task { await refreshLibrary() } } } }
                else if store.items.isEmpty { ContentUnavailableView(language.text("Your cloud library", "Votre bibliothèque cloud"), systemImage: "photo.stack", description: Text(language.text("Protected memories will appear here.", "Vos souvenirs protégés apparaîtront ici."))) }
                else { libraryContent }
            }
            .navigationTitle(isSelecting ? language.text("Select", "Sélection") : language.text("Library", "Bibliothèque"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { if !store.items.isEmpty { Button(isSelecting ? language.text("Done", "OK") : language.text("Select", "Sélectionner")) { isSelecting.toggle(); if !isSelecting { selectedIDs.removeAll() } } } } }
            .safeAreaInset(edge: .bottom, spacing: 0) { if isSelecting { selectionBar } }
            .task { await refreshLibrary() }
            .fullScreenCover(item: $viewerItem) { item in
                ProtectedGalleryViewer(items: displayItems, initialID: item.id, language: language, billing: billing)
                    .navigationTransition(.zoom(sourceID: item.id, in: photoTransition))
                    .onDisappear { Task { await refreshLibrary() } }
            }
            .sheet(isPresented: $showBulkDelete) { bulkDeleteSheet }
        }
    }

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 7) {
                if billing.isPaymentGrace { BillingLibraryNotice(language: language, restricted: false, days: billing.graceDaysRemaining) }
                else if billing.isPaymentRestricted { BillingLibraryNotice(language: language, restricted: true, days: 0) }
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.green).frame(width: 27, height: 27).background(Color.green.opacity(0.09), in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(language.text("Protected memories", "Souvenirs protégés")).font(.subheadline.weight(.semibold))
                        Text("\(filterCounts[.all, default: store.items.count].formatted()) \(language.text("items secured in Libérons", "éléments sécurisés dans Libérons"))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Menu {
                        Button { setSort(true) } label: { Label(language.text("Newest first", "Plus récents"), systemImage: sortNewestFirst ? "checkmark" : "arrow.down") }
                        Button { setSort(false) } label: { Label(language.text("Oldest first", "Plus anciens"), systemImage: !sortNewestFirst ? "checkmark" : "arrow.up") }
                    } label: {
                        HStack(spacing: 5) { Text(sortNewestFirst ? language.text("Recent", "Récents") : language.text("Oldest", "Anciens")).font(.caption.weight(.semibold)); Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)) }
                            .foregroundStyle(.primary).padding(.horizontal, 10).padding(.vertical, 7).background(.secondary.opacity(0.08), in: Capsule())
                    }
                }.padding(.horizontal, 16).padding(.top, 1)
                HStack(spacing: 4) {
                    ForEach(ProtectedLibraryFilter.allCases) { filter in
                        Button { selectFilter(filter) } label: {
                            HStack(spacing: 6) { Image(systemName: filter.icon).font(.caption.weight(.semibold)); Text(filter.title(language)).font(.subheadline.weight(.semibold)) }
                                .foregroundStyle(mediaFilter == filter ? Color.primary : Color.secondary).frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background { if mediaFilter == filter { Capsule().fill(Color(uiColor: .systemBackground)).shadow(color: .black.opacity(0.08), radius: 5, y: 2).matchedGeometryEffect(id: "activeFilter", in: filterTransition) } }
                        }.buttonStyle(.plain)
                    }
                }.padding(2.5).background(Color.secondary.opacity(0.09), in: Capsule()).padding(.horizontal, 16)
                if isSelecting { Text("\(selectedIDs.count) \(language.text("selected", "sélectionné(s)"))").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 16) }
                if displayItems.isEmpty { ContentUnavailableView(language.text("Nothing here yet", "Rien ici pour le moment"), systemImage: mediaFilter.icon).frame(maxWidth: .infinity).padding(.vertical, 42) }
                else {
                    LazyVGrid(columns: columns, spacing: 1.5) {
                        ForEach(displayItems) { item in
                            ProtectedLibraryTile(item: item).matchedTransitionSource(id: item.id, in: photoTransition)
                                .overlay(alignment: .topTrailing) { if isSelecting { Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(.white).shadow(radius: 3).padding(7) } }
                                .contentShape(Rectangle()).onTapGesture { isSelecting ? toggle(item.id) : (viewerItem = item) }
                                .onLongPressGesture(minimumDuration: 0.35) { if !isSelecting { isSelecting = true; selectedIDs = [item.id] } }
                        }
                    }
                }
            }.padding(.bottom, 132)
        }.scrollBounceBehavior(.basedOnSize).refreshable { await refreshLibrary() }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button { let visible = Set(displayItems.map(\.id)); if !visible.isEmpty && selectedIDs == visible { selectedIDs.removeAll() } else { selectedIDs = visible } } label: { Text(language.text("Select all", "Tout sélectionner")).font(.subheadline.weight(.semibold)) }
            Spacer()
            Button(role: .destructive) { showBulkDelete = true } label: { if deletingSelection { ProgressView() } else { Label(language.text("Delete from Libérons", "Supprimer de Libérons"), systemImage: "trash").font(.subheadline.weight(.semibold)) } }.disabled(selectedIDs.isEmpty || deletingSelection)
        }.padding(.horizontal, 18).padding(.vertical, 12).background(.ultraThinMaterial)
    }

    private var bulkDeleteSheet: some View {
        VStack(spacing: 18) {
            Image(systemName: "trash.fill").font(.system(size: 28, weight: .semibold)).foregroundStyle(.red).frame(width: 62, height: 62).background(Color.red.opacity(0.1), in: Circle())
            Text(language.text("Delete from Libérons?", "Supprimer de Libérons ?")).font(.title2.bold())
            Text(language.text("The selected protected memories will be permanently removed from Libérons Cloud.", "Les souvenirs protégés sélectionnés seront supprimés définitivement de Libérons Cloud.")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { showBulkDelete = false; Task { await deleteSelected() } } label: { Text(language.text("Delete permanently", "Supprimer définitivement")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).foregroundStyle(.white).background(Color.red, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain)
            Button(language.text("Cancel", "Annuler")) { showBulkDelete = false }.font(.headline)
        }.padding(24).presentationDetents([.height(390)]).presentationDragIndicator(.visible).presentationCornerRadius(30)
    }

    private func toggle(_ id: UUID) { if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) } }
    @MainActor private func selectFilter(_ filter: ProtectedLibraryFilter) { guard mediaFilter != filter else { return }; withAnimation(.snappy(duration: 0.24)) { mediaFilter = filter }; rebuildDisplayItems(); if isSelecting { selectedIDs.formIntersection(Set(displayItems.map(\.id))) } }
    @MainActor private func setSort(_ newest: Bool) { guard sortNewestFirst != newest else { return }; sortNewestFirst = newest; rebuildDisplayItems() }
    @MainActor private func rebuildDisplayItems() { var p = 0, v = 0; var visible: [ProtectedCloudMedia] = []; visible.reserveCapacity(store.items.count); for item in store.items { let video = isVideo(item); if video { v += 1 } else { p += 1 }; if mediaFilter == .all || (mediaFilter == .photos && !video) || (mediaFilter == .videos && video) { visible.append(item) } }; visible.sort { let a = $0.capturedAt ?? $0.createdAt; let b = $1.capturedAt ?? $1.createdAt; return sortNewestFirst ? a > b : a < b }; filterCounts = [.all: p + v, .photos: p, .videos: v]; displayItems = visible }
    @MainActor private func refreshLibrary() async { async let a: Void = store.refresh(); async let b: Void = billing.refresh(); _ = await (a, b); rebuildDisplayItems() }
    @MainActor private func deleteSelected() async { deletingSelection = true; for id in selectedIDs { try? await SupabaseService.deleteCloudMedia(assetID: id) }; selectedIDs.removeAll(); isSelecting = false; deletingSelection = false; await refreshLibrary() }
}

private struct BillingLibraryNotice: View {
    @ObservedObject var language: LanguageStore; let restricted: Bool; let days: Int
    var body: some View { HStack(alignment: .top, spacing: 12) { Image(systemName: restricted ? "lock.fill" : "exclamationmark.triangle.fill").foregroundStyle(restricted ? .red : .orange); VStack(alignment: .leading, spacing: 4) { Text(restricted ? language.text("Restore access paused", "Restauration suspendue") : language.text("Payment needs attention", "Paiement à régulariser")).font(.subheadline.bold()); Text(restricted ? language.text("Your memories remain protected and visible in Libérons.", "Vos souvenirs restent protégés et visibles dans Libérons.") : language.text("New backups are paused. You can still restore for about \(days) day(s).", "Les nouvelles sauvegardes sont suspendues. Restauration disponible environ \(days) jour(s)." )).font(.caption).foregroundStyle(.secondary) } }.padding(14).background((restricted ? Color.red : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 16) }
}

private struct ProtectedGalleryViewer: View {
    let items: [ProtectedCloudMedia]; let initialID: UUID
    @ObservedObject var language: LanguageStore; @ObservedObject var billing: CloudStorageSummary
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID
    @State private var showInfo = false
    @State private var dismissOffset: CGFloat = 0
    @State private var verticalDismissLocked = false
    @State private var isDismissing = false
    private let indexByID: [UUID: Int]
    init(items: [ProtectedCloudMedia], initialID: UUID, language: LanguageStore, billing: CloudStorageSummary) { self.items = items; self.initialID = initialID; self.language = language; self.billing = billing; self.indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) }); _selection = State(initialValue: initialID) }
    private var currentIndex: Int? { indexByID[selection] }
    private var current: ProtectedCloudMedia? { guard let i = currentIndex, items.indices.contains(i) else { return nil }; return items[i] }
    private var progress: CGFloat { min(max(dismissOffset / 360, 0), 1) }

    var body: some View {
        ZStack {
            Color.black.opacity(Double(1 - progress * 0.94)).ignoresSafeArea()
            if !verticalDismissLocked {
                TabView(selection: $selection) { ForEach(items) { CloudPhotoPage(item: $0, language: language, billing: billing).tag($0.id) } }
                    .tabViewStyle(.page(indexDisplayMode: .never)).ignoresSafeArea().allowsHitTesting(!isDismissing)
            } else if let current {
                CloudPhotoPage(item: current, language: language, billing: billing)
                    .id("dismiss-\(current.id)").ignoresSafeArea().offset(y: dismissOffset).scaleEffect(1 - progress * 0.10)
                    .clipShape(RoundedRectangle(cornerRadius: progress * 30, style: .continuous))
                    .shadow(color: .black.opacity(Double(progress * 0.30)), radius: 22, y: 10).allowsHitTesting(false)
            }
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title2.bold()).foregroundStyle(.white).frame(width: 48, height: 48).background(.black.opacity(0.45), in: Circle()) }.buttonStyle(.plain)
                    if let i = currentIndex { Text("\(i + 1) / \(items.count)").font(.subheadline.bold()).foregroundStyle(.white).padding(8).background(.black.opacity(0.45), in: Capsule()) }
                    Spacer()
                    Button { showInfo = true } label: { Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(.white).frame(width: 56, height: 56) }.buttonStyle(.plain)
                }.padding(.horizontal, 8).padding(.top, 4)
                Spacer()
            }.opacity(verticalDismissLocked ? Double(max(0, 1 - progress * 3.2)) : 1).allowsHitTesting(!verticalDismissLocked)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .global).onChanged { value in
            guard !isDismissing else { return }
            let x = value.translation.width, y = value.translation.height
            if !verticalDismissLocked { guard y > 6, abs(y) > abs(x) * 1.25 else { return }; verticalDismissLocked = true }
            dismissOffset = max(0, y)
        }.onEnded { value in
            guard verticalDismissLocked, !isDismissing else { return }
            let y = max(dismissOffset, value.translation.height), projected = max(y, value.predictedEndTranslation.height)
            if y > 105 || projected > 210 { isDismissing = true; withAnimation(.easeOut(duration: 0.20)) { dismissOffset = max(y, UIScreen.main.bounds.height * 0.78) }; Task { @MainActor in try? await Task.sleep(for: .milliseconds(145)); dismiss() } }
            else { withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)) { dismissOffset = 0 }; Task { @MainActor in try? await Task.sleep(for: .milliseconds(280)); verticalDismissLocked = false } }
        })
        .sheet(isPresented: $showInfo) { if let current { ProtectedMediaDetail(item: current, language: language, billing: billing, closeViewer: { showInfo = false; dismiss() }).presentationDetents([.fraction(0.46), .fraction(0.72), .large]).presentationDragIndicator(.visible).presentationCornerRadius(34).presentationBackground(.regularMaterial) } }
    }
}

private struct CloudPhotoPage: View {
    let item: ProtectedCloudMedia; @ObservedObject var language: LanguageStore; @ObservedObject var billing: CloudStorageSummary
    @State private var image: UIImage?; @State private var player: AVPlayer?; @State private var loading = true; @State private var loadFailed = false
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }
    var body: some View { ZStack { Color.black; if isVideo, let player { VideoPlayer(player: player).onAppear { player.play() } } else if let image { Image(uiImage: image).resizable().scaledToFit() } else if loading { ProgressView().tint(.white) } else { Image(systemName: loadFailed ? "exclamationmark.icloud" : "photo").foregroundStyle(.white) } }.task(id: item.id) { await load() }.onDisappear { player?.pause(); player = nil } }
    @MainActor private func load() async {
        loading = true; loadFailed = false; defer { loading = false }
        if isVideo { guard !billing.isPaymentRestricted else { loadFailed = true; return }; do { let request = try await SupabaseService.protectedStreamRequest(assetID: item.id); guard let url = request.url else { throw URLError(.badURL) }; let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": request.allHTTPHeaderFields ?? [:]]); let playable = try await asset.load(.isPlayable); guard playable else { throw URLError(.cannotDecodeContentData) }; let p = AVPlayer(playerItem: AVPlayerItem(asset: asset)); p.automaticallyWaitsToMinimizeStalling = true; player = p; p.play() } catch { loadFailed = true }; return }
        if let cached = ProtectedMediaCache.shared.image(for: item.id) { image = cached; return }
        if let id = item.iosLocalIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject { let o = PHImageRequestOptions(); o.isNetworkAccessAllowed = true; o.deliveryMode = .highQualityFormat; o.resizeMode = .fast; PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1600, height: 1600), contentMode: .aspectFit, options: o) { value, _ in if let value { ProtectedMediaCache.shared.store(value, for: self.item.id); Task { @MainActor in image = value } } }; return }
        if let url = try? await SupabaseService.cloudPreviewURL(assetID: item.id), let (data, response) = try? await URLSession.shared.data(from: url), ((response as? HTTPURLResponse)?.statusCode ?? 500) < 300, let decoded = UIImage(data: data) { ProtectedMediaCache.shared.store(decoded, for: item.id); image = decoded }
    }
}

private final class ProtectedMediaCache: @unchecked Sendable {
    static let shared = ProtectedMediaCache(); private let cache = NSCache<NSString, UIImage>()
    private init() { cache.countLimit = 220; cache.totalCostLimit = 64 * 1024 * 1024 }
    func image(for id: UUID) -> UIImage? { cache.object(forKey: id.uuidString as NSString) }
    func store(_ image: UIImage, for id: UUID) { cache.setObject(image, forKey: id.uuidString as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4)) }
}

private enum ProtectedAction: Hashable { case restore, removeDevice, deleteCloud }
private struct ProtectedMediaDetail: View {
    let item: ProtectedCloudMedia; @ObservedObject var language: LanguageStore; @ObservedObject var billing: CloudStorageSummary; var closeViewer: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss; @State private var localExists = false; @State private var localIdentifier: String?; @State private var pending: ProtectedAction?; @State private var busy = false; @State private var error: String?
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }
    var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) { HStack { VStack(alignment: .leading) { Text(item.originalFilename ?? (isVideo ? "Video" : "Photo")).font(.title3.bold()); Text(isVideo ? language.text("Video", "Vidéo") : "Photo").foregroundStyle(.secondary) }; Spacer(); Label(language.text("Protected", "Protégé"), systemImage: "checkmark.shield.fill").font(.caption.bold()).foregroundStyle(.green) }; Divider(); MetadataRow(icon: "calendar", title: language.text("Captured", "Prise le"), value: format(item.capturedAt)); MetadataRow(icon: "icloud.and.arrow.up", title: language.text("Added to Libérons", "Ajouté à Libérons le"), value: format(item.createdAt)); MetadataRow(icon: "externaldrive", title: language.text("Original size", "Taille originale"), value: ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file)); MetadataRow(icon: "iphone", title: language.text("On this iPhone", "Sur cet iPhone"), value: localExists ? language.text("Available", "Disponible") : language.text("Not on this iPhone", "Absent de cet iPhone")); Divider(); if !localExists { action(language.text("Restore to Photos", "Restaurer dans Photos"), "square.and.arrow.down", .blue) { pending = .restore } }; if localExists { action(language.text("Remove from this iPhone", "Supprimer de cet iPhone"), "iphone.slash", .red) { pending = .removeDevice } }; action(language.text("Delete permanently from Libérons", "Supprimer définitivement de Libérons"), "trash", .red) { pending = .deleteCloud }; if let error { Text(error).font(.footnote).foregroundStyle(.red) } }.padding(20) } .navigationTitle(language.text("Memory details", "Détails du souvenir")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(language.text("Done", "Fermer")) { dismiss() } } }.task { localIdentifier = item.iosLocalIdentifier; refreshLocal() }.confirmationDialog(language.text("Confirm action", "Confirmer l’action"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) { if let pending { Button(language.text("Continue", "Continuer"), role: pending == .restore ? nil : .destructive) { let a = pending; self.pending = nil; Task { await perform(a) } }; Button(language.text("Cancel", "Annuler"), role: .cancel) { pending = nil } } } }
    private func action(_ title: String, _ icon: String, _ color: Color, perform: @escaping () -> Void) -> some View { Button(action: perform) { Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(color) }.disabled(busy) }
    private func format(_ date: Date?) -> String { date?.formatted(date: .long, time: .shortened) ?? language.text("Unknown", "Inconnue") }
    private func matchingAsset() -> PHAsset? { if let id = localIdentifier { return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject }; return nil }
    private func refreshLocal() { localExists = matchingAsset() != nil }
    @MainActor private func perform(_ a: ProtectedAction) async { busy = true; defer { busy = false }; do { switch a { case .deleteCloud: _ = try await SupabaseService.deleteCloudMedia(assetID: item.id); dismiss(); closeViewer?(); case .removeDevice: if let asset = matchingAsset() { try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets([asset] as NSArray) }; localIdentifier = nil; localExists = false }; case .restore: guard !billing.isPaymentRestricted else { throw NSError(domain: "Liberons", code: 1, userInfo: [NSLocalizedDescriptionKey: language.text("Payment required before restore.", "Paiement requis avant restauration.")]) }; let remote = try await SupabaseService.cloudOriginalURL(assetID: item.id); let (temp, _) = try await URLSession.shared.download(from: remote); var newID: String?; try await PHPhotoLibrary.shared().performChanges { let r = PHAssetCreationRequest.forAsset(); r.creationDate = item.capturedAt; r.addResource(with: isVideo ? .video : .photo, fileURL: temp, options: nil); newID = r.placeholderForCreatedAsset?.localIdentifier }; if let newID { try? await SupabaseService.updateLocalIdentifier(assetID: item.id, localIdentifier: newID); localIdentifier = newID; localExists = true } } } catch { self.error = error.localizedDescription } }
}

private struct MetadataRow: View { let icon: String; let title: String; let value: String; var body: some View { HStack(alignment: .top, spacing: 13) { Image(systemName: icon).frame(width: 24).foregroundStyle(.blue); VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.bold()) }; Spacer() } } }

private struct ProtectedLibraryTile: View {
    let item: ProtectedCloudMedia; @State private var image: UIImage?; @State private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }
    var body: some View { ZStack { GeometryReader { proxy in ZStack { Rectangle().fill(Color.secondary.opacity(0.06)); if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped() } else { Image(systemName: isVideo ? "video.fill" : "photo.fill").font(.system(size: 17)).foregroundStyle(.tertiary) } } }.aspectRatio(1, contentMode: .fit); if isVideo { VStack { Spacer(); HStack { Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 25, height: 25).background(.black.opacity(0.48), in: Circle()).padding(6); Spacer() } } } }.task(id: item.id) { await loadThumbnail() }.onDisappear { if requestID != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(requestID); requestID = PHInvalidImageRequestID } } }
    @MainActor private func loadThumbnail() async {
        if let cached = ProtectedMediaCache.shared.image(for: item.id) { image = cached; return }
        if let id = item.iosLocalIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject { let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = false; options.deliveryMode = .opportunistic; options.resizeMode = .fast; let scale = UIScreen.main.scale; let side = min(UIScreen.main.bounds.width / 3 * scale, 420); requestID = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options) { value, _ in if let value { ProtectedMediaCache.shared.store(value, for: self.item.id); Task { @MainActor in image = value } } }; return }
        if let preview = try? await SupabaseService.cloudPreviewURL(assetID: item.id), let (data, response) = try? await URLSession.shared.data(from: preview), ((response as? HTTPURLResponse)?.statusCode ?? 500) < 300, let decoded = UIImage(data: data) { ProtectedMediaCache.shared.store(decoded, for: item.id); image = decoded }
    }
}
