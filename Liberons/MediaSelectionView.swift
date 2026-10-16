import SwiftUI
import Photos

struct MediaSelectionView: View {
    @ObservedObject var backup: BackupEngine
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var selected = Set<String>()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        Button { toggle(asset) } label: {
                            ZStack(alignment: .topTrailing) {
                                SelectionThumbnail(asset: asset).aspectRatio(1, contentMode: .fill).clipped()
                                Image(systemName: selected.contains(asset.localIdentifier) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3.bold()).foregroundStyle(selected.contains(asset.localIdentifier) ? .blue : .white)
                                    .padding(7).shadow(radius: 2)
                                if asset.mediaType == .video { Image(systemName: "video.fill").font(.caption).foregroundStyle(.white).padding(7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).shadow(radius: 2) }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(language.text("Choose what to protect", "Choisir quoi protéger"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Text(language.text("Oldest memories are shown first. Tap only the photos and videos you want Libérons to protect.", "Les souvenirs les plus anciens sont affichés en premier. Touchez uniquement les photos et vidéos que Libérons doit protéger."))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button {
                        let ids = assets.filter { selected.contains($0.localIdentifier) }.map(\.localIdentifier)
                        dismiss(); Task { await backup.backup(localIdentifiers: ids) }
                    } label: {
                        Text(language.text("Protect \(selected.count) selected", "Protéger les \(selected.count) sélectionnés")).fontWeight(.semibold).frame(maxWidth: .infinity).frame(height: 34)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(selected.isEmpty || backup.isRunning)
                }.padding().background(.ultraThinMaterial)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(language.text("Cancel", "Annuler")) { dismiss() } }; ToolbarItem(placement: .topBarTrailing) { Button(selected.count == assets.count ? language.text("Clear", "Effacer") : language.text("Select all", "Tout sélectionner")) { if selected.count == assets.count { selected.removeAll() } else { selected = Set(assets.map(\.localIdentifier)) } } } }
            .task { loadOldest() }
        }
    }

    private func loadOldest() {
        let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options); var loaded: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in loaded.append(asset) }; assets = loaded
    }
    private func toggle(_ asset: PHAsset) { if selected.contains(asset.localIdentifier) { selected.remove(asset.localIdentifier) } else { selected.insert(asset.localIdentifier) } }
}

private struct SelectionThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    var body: some View {
        ZStack { Rectangle().fill(.secondary.opacity(0.12)); if let image { Image(uiImage: image).resizable().scaledToFill() } else { ProgressView() } }
            .task(id: asset.localIdentifier) {
                let options = PHImageRequestOptions(); options.deliveryMode = .opportunistic; options.resizeMode = .fast; options.isNetworkAccessAllowed = true
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options) { value, _ in if let value { Task { @MainActor in image = value } } }
            }
    }
}
