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
    @State private var showingPreview = false
    @State private var filter: MediaFilter = .all

    private enum MediaFilter: String, CaseIterable, Identifiable {
        case all, photos, videos, screenshots
        var id: String { rawValue }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    private var filteredAssets: [PHAsset] {
        let base: [PHAsset]
        switch filter {
        case .all:
            base = assets
        case .photos:
            base = assets.filter { $0.mediaType == .image && !$0.mediaSubtypes.contains(.photoScreenshot) }
        case .videos:
            base = assets.filter { $0.mediaType == .video }
        case .screenshots:
            base = assets.filter { $0.mediaType == .image && $0.mediaSubtypes.contains(.photoScreenshot) }
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
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(filteredAssets.enumerated()), id: \.element.localIdentifier) { index, asset in
                            let isSelected = selected.contains(asset.localIdentifier)
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    previewIndex = index
                                    showingPreview = true
                                } label: {
                                    SelectionThumbnail(asset: asset)
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay { if isSelected { Color.accentColor.opacity(0.10) } }
                                        .overlay { if isSelected { Rectangle().strokeBorder(Color.accentColor, lineWidth: 3) } }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    withAnimation(.easeOut(duration: 0.12)) { toggle(asset) }
                                } label: {
                                    ZStack {
                                        Circle().fill(isSelected ? Color.accentColor : Color.black.opacity(0.50)).frame(width: 28, height: 28)
                                        Image(systemName: isSelected ? "checkmark" : "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                    }
                                    .padding(7)
                                }
                                .buttonStyle(.plain)

                                if asset.mediaType == .video {
                                    HStack(spacing: 3) {
                                        Image(systemName: "play.fill")
                                        Text(duration(asset.duration))
                                    }
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.58), in: Capsule())
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                    .padding(6)
                                    .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 110)
                }
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
                            Button(language.text("Clear", "Effacer")) {
                                selected.removeAll()
                                showSelectedOnly = false
                            }
                            .font(.subheadline)
                        }
                    }
                    Button {
                        let ids = assets.filter { selected.contains($0.localIdentifier) }.map(\.localIdentifier)
                        dismiss()
                        Task { await backup.backup(localIdentifiers: ids) }
                    } label: {
                        Label(language.text("Protect selected media", "Protéger les médias sélectionnés"), systemImage: "icloud.and.arrow.up.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selected.isEmpty || backup.isRunning)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(language.text("Cancel", "Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !selected.isEmpty {
                            Button(showSelectedOnly ? language.text("Show all", "Tout voir") : language.text("Show selected", "Voir la sélection")) {
                                withAnimation { showSelectedOnly.toggle() }
                            }
                        }
                        Button(language.text("Select visible", "Tout sélectionner ici")) {
                            selected.formUnion(filteredAssets.map(\.localIdentifier))
                            showSelectedOnly = false
                        }
                        if !selected.isEmpty {
                            Button(language.text("Clear selection", "Effacer la sélection"), role: .destructive) {
                                selected.removeAll()
                                showSelectedOnly = false
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fullScreenCover(isPresented: $showingPreview) {
                MediaPreviewGallery(assets: filteredAssets, initialIndex: previewIndex, selected: $selected, language: language)
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
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
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                filter = value
                showSelectedOnly = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
                Text(count.formatted()).font(.caption.bold()).opacity(0.75)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(active ? Color.white : Color.primary)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(active ? Color.accentColor : Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadOldest() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var loaded: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image || asset.mediaType == .video { loaded.append(asset) }
        }
        assets = loaded
    }

    private func toggle(_ asset: PHAsset) {
        if selected.contains(asset.localIdentifier) { selected.remove(asset.localIdentifier) }
        else { selected.insert(asset.localIdentifier) }
    }

    private func duration(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct MediaPreviewGallery: View {
    let assets: [PHAsset]
    @Binding var selected: Set<String>
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var verticalOffset: CGFloat = 0
    @State private var pageIsZoomed = false

    init(assets: [PHAsset], initialIndex: Int, selected: Binding<Set<String>>, language: LanguageStore) {
        self.assets = assets
        self._selected = selected
        self.language = language
        self._currentIndex = State(initialValue: initialIndex)
    }

    private var backdropOpacity: Double {
        let distance = Double(abs(verticalOffset))
        return Swift.max(0.55, 1.0 - distance / 600.0)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity).ignoresSafeArea()
            TabView(selection: $currentIndex) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    ZoomablePreviewPage(asset: asset, isZoomed: $pageIsZoomed).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(pageIsZoomed)
            .offset(y: pageIsZoomed ? 0 : verticalOffset)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white).frame(width: 42, height: 42).background(.black.opacity(0.48), in: Circle())
                    }
                    Spacer()
                    if assets.indices.contains(currentIndex) {
                        let asset = assets[currentIndex]
                        let isSelected = selected.contains(asset.localIdentifier)
                        Button {
                            if isSelected { selected.remove(asset.localIdentifier) }
                            else { selected.insert(asset.localIdentifier) }
                        } label: {
                            Label(isSelected ? language.text("Selected", "Sélectionné") : language.text("Select", "Sélectionner"), systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline.bold()).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 42)
                                .background(isSelected ? Color.accentColor : Color.black.opacity(0.48), in: Capsule())
                        }
                    }
                }
                .padding()
                Spacer()
                if assets.indices.contains(currentIndex), let date = assets[currentIndex].creationDate {
                    Text(date.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.5), in: Capsule()).padding(.bottom, 16)
                }
            }
            .opacity(pageIsZoomed ? 0 : 1)
            .offset(y: verticalOffset)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard !pageIsZoomed else { return }
                    if abs(value.translation.height) > abs(value.translation.width) { verticalOffset = value.translation.height }
                }
                .onEnded { value in
                    guard !pageIsZoomed else { return }
                    if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 220 { dismiss() }
                    else { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { verticalOffset = 0 } }
                }
        )
        .onChange(of: currentIndex) { _, _ in
            pageIsZoomed = false
            verticalOffset = 0
        }
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
                    if let player {
                        VideoPlayer(player: player).onAppear { player.play() }.onDisappear { player.pause() }
                    } else { ProgressView().tint(.white) }
                } else if let finalImage = image {
                    fittedImage(finalImage, in: proxy.size)
                } else if let previewImage = degradedImage {
                    fittedImage(previewImage, in: proxy.size).blur(radius: 3)
                } else {
                    VStack(spacing: 12) { ProgressView().tint(.white); Text("Loading…").font(.caption).foregroundStyle(.white.opacity(0.72)) }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        guard asset.mediaType != .video else { return }
                        let next = min(max(lastScale * value, 1), 5)
                        scale = next
                        isZoomed = next > 1.01
                    }
                    .onEnded { _ in
                        if scale < 1.05 { resetZoom() }
                        else { lastScale = scale }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard asset.mediaType != .video, scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in
                        guard asset.mediaType != .video, scale > 1 else { return }
                        lastOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                guard asset.mediaType != .video else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    if scale > 1 { resetZoom() }
                    else { scale = 2.5; lastScale = 2.5; isZoomed = true }
                }
            }
        }
        .task(id: asset.localIdentifier) { requestMedia() }
        .onDisappear {
            if requestID != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(requestID) }
            player?.pause()
            player = nil
            resetZoom()
        }
    }

    @ViewBuilder
    private func fittedImage(_ uiImage: UIImage, in size: CGSize) -> some View {
        Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fit).frame(width: size.width, height: size.height).scaleEffect(scale).offset(offset)
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        isZoomed = false
    }

    private func requestMedia() {
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                guard let item else { return }
                Task { @MainActor in player = AVPlayer(playerItem: item) }
            }
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let screen = UIScreen.main.bounds.size
        let screenScale = UIScreen.main.scale
        requestID = PHCachingImageManager.default().requestImage(for: asset, targetSize: CGSize(width: screen.width * screenScale, height: screen.height * screenScale), contentMode: .aspectFit, options: options) { value, info in
            guard let value else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            Task { @MainActor in
                if degraded { degradedImage = value }
                else { image = value }
            }
        }
    }
}

private struct SelectionThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.secondary.opacity(0.08)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else { ProgressView() }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: asset.localIdentifier) {
            let scale = UIScreen.main.scale
            let side = 180 * scale
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options) { value, _ in
                if let value { Task { @MainActor in image = value } }
            }
        }
    }
}
