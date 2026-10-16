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
            }.navigationTitle(language.text("Library", "Bibliothèque")).task { await store.refresh() }.sheet(item: $selected) { item in ProtectedMediaDetail(item: item, language: language) }
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
                        MetadataRow(icon: "iphone", title: language.text("On this iPhone", "Sur cet iPhone"), value: item.localRemovedAt == nil ? language.text("Original still on device", "Original encore sur l’appareil") : language.text("Local original removed", "Original local supprimé"))
                        Label(language.text("Loaded securely from Libérons Cloud.", "Chargé de manière sécurisée depuis Libérons Cloud."), systemImage: "icloud.fill").font(.footnote).foregroundStyle(.secondary)
                    }.padding(20)
                }
            }.ignoresSafeArea(edges: .top).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(language.text("Done", "Fermer")) { dismiss() } } }.task { await loadFromCloud() }
        }
    }
    private func format(_ date: Date?) -> String { guard let date else { return language.text("Unknown", "Inconnue") }; return date.formatted(date: .long, time: .shortened) }
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
