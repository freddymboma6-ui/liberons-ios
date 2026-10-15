import SwiftUI
import Photos

struct ProtectedLibraryView: View {
    @ObservedObject var language: LanguageStore
    @StateObject private var store = ProtectedMediaStore()

    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.items.isEmpty {
                    ProgressView(language.text("Loading your library…", "Chargement de votre bibliothèque…"))
                } else if let error = store.errorMessage, store.items.isEmpty {
                    ContentUnavailableView {
                        Label(language.text("Library unavailable", "Bibliothèque indisponible"), systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(error)
                    } actions: {
                        Button(language.text("Try again", "Réessayer")) { Task { await store.refresh() } }
                    }
                } else if store.items.isEmpty {
                    ContentUnavailableView(language.text("Your cloud library", "Votre bibliothèque cloud"), systemImage: "photo.stack", description: Text(language.text("Protected memories will appear here.", "Vos souvenirs protégés apparaîtront ici.")))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(store.items) { item in
                                ProtectedLibraryTile(item: item)
                            }
                        }
                        .padding(.bottom, 100)
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle(language.text("Library", "Bibliothèque"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.items.isEmpty {
                        Text("\(store.items.count)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .task { await store.refresh() }
        }
    }
}

private struct ProtectedLibraryTile: View {
    let item: ProtectedCloudMedia
    @State private var image: UIImage?

    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.10))
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                    } else {
                        Image(systemName: isVideo ? "video.fill" : "photo.fill").font(.title2).foregroundStyle(.secondary)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            if isVideo {
                Image(systemName: "play.fill").font(.caption.bold()).foregroundStyle(.white).padding(7).background(.black.opacity(0.55), in: Circle()).padding(7)
            }

            Image(systemName: "checkmark.shield.fill").font(.caption).foregroundStyle(.white).padding(6).background(.green.opacity(0.9), in: Circle()).padding(7)
                .offset(x: isVideo ? -34 : 0)
        }
        .task(id: item.iosLocalIdentifier) { loadThumbnail() }
        .accessibilityLabel(item.originalFilename ?? (isVideo ? "Video" : "Photo"))
    }

    private func loadThumbnail() {
        guard let identifier = item.iosLocalIdentifier else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 500, height: 500), contentMode: .aspectFill, options: options) { value, _ in
            guard let value else { return }
            Task { @MainActor in image = value }
        }
    }
}
