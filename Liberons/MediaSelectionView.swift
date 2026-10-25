import SwiftUI
import Photos
import UIKit
import AVKit

struct MediaSelectionView: View {
    @ObservedObject var backup: BackupEngine
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var selected = Set<String>()
    @State private var showSelectedOnly = false
    @State private var previewIndex = 0
    @State private var previewAssets: [PHAsset] = []
    @State private var showingPreview = false
    @State private var filter: MediaFilter = .all

    private enum MediaFilter: String, CaseIterable, Identifiable {
        case all, photos, videos, screenshots
        var id: String { rawValue }
    }

    private var filteredAssets: [PHAsset] {
        let base: [PHAsset]
        switch filter {
        case .all: base = assets
        case .photos: base = assets.filter { $0.mediaType == .image && !$0.mediaSubtypes.contains(.photoScreenshot) }
        case .videos: base = assets.filter { $0.mediaType == .video }
        case .screenshots: base = assets.filter { $0.mediaType == .image && $0.mediaSubtypes.contains(.photoScreenshot) }
        }
        return showSelectedOnly ? base.filter { selected.contains($0.localIdentifier) } : base
    }

    private var photoCount: Int { assets.filter { $0.mediaType == .image && !$0.mediaSubtypes.contains(.photoScreenshot) }.count }
    private var videoCount: Int { assets.filter { $0.mediaType == .video }.count }
    private var screenshotCount: Int { assets.filter { $0.mediaType == .image && $0.mediaSubtypes.contains(.photoScreenshot) }.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                NativeMediaGrid(
                    assets: filteredAssets,
                    selected: $selected,
                    onOpen: { index in
                        let snapshot = filteredAssets
                        guard snapshot.indices.contains(index) else { return }
                        previewAssets = snapshot
                        previewIndex = index
                        showingPreview = true
                    }
                )
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(language.text("Choose media", "Choisir les médias"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 9) {
                    HStack {
                        Text(selected.isEmpty ? language.text("Nothing selected", "Aucune sélection") : language.text("\(selected.count) selected", "\(selected.count) sélectionnés")).font(.subheadline.bold())
                        Spacer()
                        if !selected.isEmpty {
                            Button(language.text("Clear", "Effacer")) { selected.removeAll(); showSelectedOnly = false }.font(.subheadline)
                        }
                    }
                    Button {
                        let ids = assets.filter { selected.contains($0.localIdentifier) }.map(\.localIdentifier)
                        dismiss()
                        Task { await backup.backup(localIdentifiers: ids) }
                    } label: {
                        Label(language.text("Protect selected media", "Protéger les médias sélectionnés"), systemImage: "icloud.and.arrow.up.fill")
                            .fontWeight(.semibold).frame(maxWidth: .infinity).frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(selected.isEmpty || backup.isRunning)
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6).background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(language.text("Cancel", "Annuler")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !selected.isEmpty {
                            Button(showSelectedOnly ? language.text("Show all", "Tout voir") : language.text("Show selected", "Voir la sélection")) { withAnimation { showSelectedOnly.toggle() } }
                        }
                        Button(language.text("Select visible", "Tout sélectionner ici")) { selected.formUnion(filteredAssets.map(\.localIdentifier)); showSelectedOnly = false }
                        if !selected.isEmpty {
                            Button(language.text("Clear selection", "Effacer la sélection"), role: .destructive) { selected.removeAll(); showSelectedOnly = false }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .fullScreenCover(isPresented: $showingPreview) {
                MediaPreviewGallery(assets: previewAssets, initialIndex: previewIndex, selected: $selected, language: language)
            }
            .task { loadOldest() }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(.all, icon: "square.grid.2x2.fill", count: assets.count)
                filterChip(.photos, icon: "photo.fill", count: photoCount)
                filterChip(.videos, icon: "video.fill", count: videoCount)
                filterChip(.screenshots, icon: "iphone", count: screenshotCount)
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }.background(.ultraThinMaterial)
    }

    private func filterChip(_ value: MediaFilter, icon: String, count: Int) -> some View {
        let active = filter == value
        let label: String = {
            switch value {
            case .all: return language.text("All", "Tout")
            case .photos: return language.text("Photos", "Photos")
            case .videos: return language.text("Videos", "Vidéos")
            case .screenshots: return language.text("Screenshots", "Captures")
            }
        }()
        return Button { withAnimation(.easeInOut(duration: 0.18)) { filter = value; showSelectedOnly = false } } label: {
            HStack(spacing: 6) { Image(systemName: icon); Text(label); Text(count.formatted()).font(.caption.bold()).opacity(0.75) }
                .font(.subheadline.weight(.semibold)).foregroundStyle(active ? Color.white : Color.primary)
                .padding(.horizontal, 13).frame(height: 36)
                .background(active ? Color.accentColor : Color(uiColor: .secondarySystemBackground), in: Capsule())
        }.buttonStyle(.plain)
    }

    private func loadOldest() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var loaded: [PHAsset] = []
        loaded.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in if asset.mediaType == .image || asset.mediaType == .video { loaded.append(asset) } }
        assets = loaded
    }
}

private struct NativeMediaGrid: UIViewRepresentable {
    let assets: [PHAsset]
    @Binding var selected: Set<String>
    let onOpen: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 2; layout.minimumInteritemSpacing = 2
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .systemBackground
        view.contentInset = UIEdgeInsets(top: 2, left: 2, bottom: 110, right: 2)
        view.alwaysBounceVertical = true
        view.dataSource = context.coordinator; view.delegate = context.coordinator; view.prefetchDataSource = context.coordinator
        view.isPrefetchingEnabled = true
        view.register(MediaGridCell.self, forCellWithReuseIdentifier: MediaGridCell.reuseIdentifier)
        context.coordinator.collectionView = view
        return view
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) { context.coordinator.update(parent: self) }
    static func dismantleUIView(_ uiView: UICollectionView, coordinator: Coordinator) { coordinator.stopAllCaching() }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {
        private var parent: NativeMediaGrid
        private let imageManager = PHCachingImageManager()
        private let options: PHImageRequestOptions = {
            let value = PHImageRequestOptions(); value.deliveryMode = .opportunistic; value.resizeMode = .fast; value.isNetworkAccessAllowed = true; return value
        }()
        weak var collectionView: UICollectionView?
        private var assetIDs: [String]
        private var cachedIndexes = Set<Int>()
        private var thumbnailSize: CGSize = .zero

        init(parent: NativeMediaGrid) { self.parent = parent; self.assetIDs = parent.assets.map(\.localIdentifier) }

        func update(parent: NativeMediaGrid) {
            let newIDs = parent.assets.map(\.localIdentifier)
            let dataChanged = newIDs != assetIDs
            let selectionChanged = parent.selected != self.parent.selected
            self.parent = parent
            if dataChanged {
                stopAllCaching(); assetIDs = newIDs; collectionView?.reloadData()
            } else if selectionChanged, let collectionView {
                for indexPath in collectionView.indexPathsForVisibleItems {
                    guard parent.assets.indices.contains(indexPath.item), let cell = collectionView.cellForItem(at: indexPath) as? MediaGridCell else { continue }
                    cell.setSelected(parent.selected.contains(parent.assets[indexPath.item].localIdentifier))
                }
            }
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { parent.assets.count }

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let width = floor((collectionView.bounds.width - 8) / 3)
            let pixels = width * UIScreen.main.scale
            thumbnailSize = CGSize(width: pixels, height: pixels)
            return CGSize(width: width, height: width)
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MediaGridCell.reuseIdentifier, for: indexPath) as? MediaGridCell,
                  parent.assets.indices.contains(indexPath.item) else { return UICollectionViewCell() }
            let asset = parent.assets[indexPath.item]
            cell.configurePlaceholder(assetID: asset.localIdentifier, selected: parent.selected.contains(asset.localIdentifier), duration: asset.mediaType == .video ? duration(asset.duration) : nil)
            requestThumbnail(for: asset, cell: cell)
            cell.onSelection = { [weak self, weak cell] in
                guard let self else { return }
                let id = asset.localIdentifier
                if self.parent.selected.contains(id) { self.parent.selected.remove(id) } else { self.parent.selected.insert(id) }
                cell?.setSelected(self.parent.selected.contains(id))
            }
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard parent.assets.indices.contains(indexPath.item) else { return }; parent.onOpen(indexPath.item)
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let indexes = indexPaths.map(\.item).filter { parent.assets.indices.contains($0) && !cachedIndexes.contains($0) }
            guard !indexes.isEmpty else { return }
            cachedIndexes.formUnion(indexes)
            imageManager.startCachingImages(for: indexes.map { parent.assets[$0] }, targetSize: effectiveThumbnailSize(collectionView), contentMode: .aspectFill, options: options)
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            let indexes = indexPaths.map(\.item).filter { parent.assets.indices.contains($0) && cachedIndexes.contains($0) }
            guard !indexes.isEmpty else { return }
            imageManager.stopCachingImages(for: indexes.map { parent.assets[$0] }, targetSize: effectiveThumbnailSize(collectionView), contentMode: .aspectFill, options: options)
            cachedIndexes.subtract(indexes)
        }

        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            (cell as? MediaGridCell)?.cancelImageRequest(using: imageManager)
        }

        private func requestThumbnail(for asset: PHAsset, cell: MediaGridCell) {
            cell.cancelImageRequest(using: imageManager)
            let representedID = asset.localIdentifier
            cell.requestID = imageManager.requestImage(for: asset, targetSize: effectiveThumbnailSize(collectionView), contentMode: .aspectFill, options: options) { [weak cell] image, _ in
                guard let cell, cell.representedAssetID == representedID, let image else { return }; cell.setImage(image)
            }
        }

        private func effectiveThumbnailSize(_ collectionView: UICollectionView?) -> CGSize {
            if thumbnailSize.width > 0 { return thumbnailSize }
            let width = max(120, ((collectionView?.bounds.width ?? UIScreen.main.bounds.width) - 8) / 3)
            let pixels = width * UIScreen.main.scale
            return CGSize(width: pixels, height: pixels)
        }

        private func duration(_ value: TimeInterval) -> String {
            let total = Int(value.rounded())
            return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
        }

        func stopAllCaching() { imageManager.stopCachingImagesForAllAssets(); cachedIndexes.removeAll() }
    }
}

private final class MediaGridCell: UICollectionViewCell {
    static let reuseIdentifier = "LiberonsMediaGridCell"
    private let imageView = UIImageView()
    private let selectionButton = UIButton(type: .system)
    private let durationLabel = UILabel()
    private let selectionOverlay = UIView()
    var representedAssetID: String?
    var requestID: PHImageRequestID = PHInvalidImageRequestID
    var onSelection: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill; imageView.clipsToBounds = true; imageView.backgroundColor = .secondarySystemBackground
        selectionOverlay.backgroundColor = UIColor.tintColor.withAlphaComponent(0.10); selectionOverlay.layer.borderColor = UIColor.tintColor.cgColor; selectionOverlay.layer.borderWidth = 3; selectionOverlay.isUserInteractionEnabled = false
        selectionButton.tintColor = .white; selectionButton.backgroundColor = UIColor.black.withAlphaComponent(0.48); selectionButton.layer.cornerRadius = 14; selectionButton.addTarget(self, action: #selector(toggleSelection), for: .touchUpInside)
        durationLabel.font = .systemFont(ofSize: 11, weight: .bold); durationLabel.textColor = .white; durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.58); durationLabel.layer.cornerRadius = 9; durationLabel.clipsToBounds = true; durationLabel.textAlignment = .center
        [imageView, selectionOverlay, selectionButton, durationLabel].forEach { contentView.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), imageView.topAnchor.constraint(equalTo: contentView.topAnchor), imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            selectionOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), selectionOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), selectionOverlay.topAnchor.constraint(equalTo: contentView.topAnchor), selectionOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            selectionButton.widthAnchor.constraint(equalToConstant: 28), selectionButton.heightAnchor.constraint(equalToConstant: 28), selectionButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7), selectionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -7),
            durationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6), durationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6), durationLabel.heightAnchor.constraint(equalToConstant: 18), durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() { super.prepareForReuse(); representedAssetID = nil; imageView.image = nil; durationLabel.text = nil; durationLabel.isHidden = true; onSelection = nil; requestID = PHInvalidImageRequestID }

    func configurePlaceholder(assetID: String, selected: Bool, duration: String?) {
        representedAssetID = assetID; imageView.image = nil; durationLabel.text = duration.map { "  ▶︎  \($0)  " }; durationLabel.isHidden = duration == nil; setSelected(selected)
    }
    func setImage(_ image: UIImage) { imageView.image = image }
    func setSelected(_ selected: Bool) {
        selectionOverlay.isHidden = !selected
        selectionButton.backgroundColor = selected ? .tintColor : UIColor.black.withAlphaComponent(0.48)
        selectionButton.setImage(UIImage(systemName: selected ? "checkmark" : "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), for: .normal)
    }
    func cancelImageRequest(using manager: PHImageManager) { if requestID != PHInvalidImageRequestID { manager.cancelImageRequest(requestID); requestID = PHInvalidImageRequestID } }
    @objc private func toggleSelection() { onSelection?() }
}

private struct MediaPreviewGallery: View {
    let assets: [PHAsset]
    @Binding var selected: Set<String>
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var currentAssetID: String
    @State private var verticalOffset: CGFloat = 0
    @State private var pageIsZoomed = false

    init(assets: [PHAsset], initialIndex: Int, selected: Binding<Set<String>>, language: LanguageStore) {
        self.assets = assets
        self._selected = selected
        self.language = language
        let safeIndex = assets.indices.contains(initialIndex) ? initialIndex : 0
        self._currentAssetID = State(initialValue: assets.indices.contains(safeIndex) ? assets[safeIndex].localIdentifier : "")
    }

    private var currentIndex: Int? { assets.firstIndex { $0.localIdentifier == currentAssetID } }
    private var currentAsset: PHAsset? { guard let currentIndex, assets.indices.contains(currentIndex) else { return nil }; return assets[currentIndex] }
    private var backdropOpacity: Double { Swift.max(0.55, 1.0 - Double(abs(verticalOffset)) / 600.0) }

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity).ignoresSafeArea()
            TabView(selection: $currentAssetID) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    ZoomablePreviewPage(asset: asset, isZoomed: $pageIsZoomed)
                        .tag(asset.localIdentifier)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(pageIsZoomed)
            .offset(y: pageIsZoomed ? 0 : verticalOffset)

            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).foregroundStyle(.white).frame(width: 42, height: 42).background(.black.opacity(0.48), in: Circle()) }
                    Spacer()
                    if let asset = currentAsset {
                        let isSelected = selected.contains(asset.localIdentifier)
                        Button {
                            if isSelected { selected.remove(asset.localIdentifier) } else { selected.insert(asset.localIdentifier) }
                        } label: {
                            Label(isSelected ? language.text("Selected", "Sélectionné") : language.text("Select", "Sélectionner"), systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline.bold()).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 42)
                                .background(isSelected ? Color.accentColor : Color.black.opacity(0.48), in: Capsule())
                        }
                    }
                }.padding()
                Spacer()
                if let date = currentAsset?.creationDate {
                    Text(date.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.5), in: Capsule()).padding(.bottom, 16)
                }
            }.opacity(pageIsZoomed ? 0 : 1).offset(y: verticalOffset)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { value in
            guard !pageIsZoomed else { return }
            if abs(value.translation.height) > abs(value.translation.width) { verticalOffset = value.translation.height }
        }.onEnded { value in
            guard !pageIsZoomed else { return }
            if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 220 { dismiss() }
            else { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { verticalOffset = 0 } }
        })
        .onChange(of: currentAssetID) { _, _ in pageIsZoomed = false; verticalOffset = 0 }
    }
}

private struct ZoomablePreviewPage: View {
    let asset: PHAsset
    @Binding var isZoomed: Bool
    @State private var image: UIImage?
    @State private var degradedImage: UIImage?
    @State private var player: AVPlayer?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if asset.mediaType == .video {
                    if let player { VideoPlayer(player: player).onAppear { player.play() }.onDisappear { player.pause() } }
                    else { ProgressView().tint(.white) }
                } else if let image { fittedImage(image, in: proxy.size) }
                else if let degradedImage { fittedImage(degradedImage, in: proxy.size).blur(radius: 3) }
                else { VStack(spacing: 12) { ProgressView().tint(.white); Text("Loading…").font(.caption).foregroundStyle(.white.opacity(0.72)) } }
            }
            .frame(width: proxy.size.width, height: proxy.size.height).clipped().contentShape(Rectangle())
            .gesture(MagnificationGesture().onChanged { value in
                guard asset.mediaType != .video else { return }; let next = min(max(lastScale * value, 1), 5); scale = next; isZoomed = next > 1.01
            }.onEnded { _ in if scale < 1.05 { resetZoom() } else { lastScale = scale } })
            .simultaneousGesture(DragGesture().onChanged { value in
                guard asset.mediaType != .video, scale > 1 else { return }; offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }.onEnded { _ in guard asset.mediaType != .video, scale > 1 else { return }; lastOffset = offset })
            .onTapGesture(count: 2) {
                guard asset.mediaType != .video else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { if scale > 1 { resetZoom() } else { scale = 2.5; lastScale = 2.5; isZoomed = true } }
            }
        }
        .task(id: asset.localIdentifier) { requestMedia() }
        .onDisappear { if requestID != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(requestID) }; player?.pause(); player = nil; resetZoom() }
    }

    @ViewBuilder private func fittedImage(_ uiImage: UIImage, in size: CGSize) -> some View {
        Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fit).frame(width: size.width, height: size.height).scaleEffect(scale).offset(offset)
    }

    private func resetZoom() { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero; isZoomed = false }

    private func requestMedia() {
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions(); options.deliveryMode = .automatic; options.isNetworkAccessAllowed = true
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                guard let item else { return }
                Task { @MainActor in player = AVPlayer(playerItem: item) }
            }
            return
        }
        let options = PHImageRequestOptions(); options.deliveryMode = .opportunistic; options.resizeMode = .fast; options.isNetworkAccessAllowed = true
        let screen = UIScreen.main.bounds.size; let screenScale = UIScreen.main.scale
        requestID = PHCachingImageManager.default().requestImage(for: asset, targetSize: CGSize(width: screen.width * screenScale, height: screen.height * screenScale), contentMode: .aspectFit, options: options) { value, info in
            guard let value else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            Task { @MainActor in if degraded { degradedImage = value } else { image = value } }
        }
    }
}
