import SwiftUI
import UIKit
import Photos
import AVFoundation
import ImageIO

/// High-performance protected-media grid backed by UICollectionView.
/// Stable UUID identities, reusable cells, PhotoKit caching and cloud prefetching
/// keep scrolling independent from the number of protected memories.
struct ProtectedNativeLibraryGrid: UIViewRepresentable {
    let items: [ProtectedCloudMedia]
    let selectedIDs: Set<UUID>
    let isSelecting: Bool
    let onTap: (ProtectedCloudMedia) -> Void
    let onLongPress: (ProtectedCloudMedia) -> Void
    let onNeedsMore: (ProtectedCloudMedia) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 1.5
        layout.minimumLineSpacing = 1.5
        layout.sectionInset = .zero

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(ProtectedNativeMediaCell.self, forCellWithReuseIdentifier: ProtectedNativeMediaCell.reuseID)
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        collectionView.addGestureRecognizer(longPress)

        context.coordinator.attach(to: collectionView)
        context.coordinator.update(parent: self, in: collectionView, animated: false)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.update(parent: self, in: collectionView, animated: true)
    }

    @MainActor
    final class Coordinator: NSObject, @MainActor UICollectionViewDelegateFlowLayout, @MainActor UICollectionViewDataSourcePrefetching {
        private enum Section: Hashable, Sendable { case main }

        private var parent: ProtectedNativeLibraryGrid
        private var itemsByID: [UUID: ProtectedCloudMedia] = [:]
        private var orderedIDs: [UUID] = []
        private weak var collectionView: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Section, UUID>?
        private let pipeline = ProtectedGridImagePipeline.shared
        private var lastPaginationID: UUID?

        init(parent: ProtectedNativeLibraryGrid) {
            self.parent = parent
            super.init()
        }

        func attach(to collectionView: UICollectionView) {
            self.collectionView = collectionView
            dataSource = UICollectionViewDiffableDataSource<Section, UUID>(collectionView: collectionView) { [weak self] collectionView, indexPath, id in
                guard let self,
                      let item = self.itemsByID[id],
                      let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ProtectedNativeMediaCell.reuseID, for: indexPath) as? ProtectedNativeMediaCell else { return nil }

                cell.configure(id: id, isVideo: self.isVideo(item), selected: self.parent.selectedIDs.contains(id), selecting: self.parent.isSelecting)
                self.loadThumbnail(for: item, into: cell)
                return cell
            }
        }

        func update(parent: ProtectedNativeLibraryGrid, in collectionView: UICollectionView, animated: Bool) {
            self.parent = parent
            let newIDs = parent.items.map(\.id)
            itemsByID = Dictionary(uniqueKeysWithValues: parent.items.map { ($0.id, $0) })

            if newIDs != orderedIDs {
                orderedIDs = newIDs
                var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
                snapshot.appendSections([Section.main])
                snapshot.appendItems(newIDs, toSection: Section.main)
                dataSource?.apply(snapshot, animatingDifferences: animated && !collectionView.isDragging)
            } else {
                // Selection changes don't alter identity/order. Reconfigure only visible cells.
                for indexPath in collectionView.indexPathsForVisibleItems {
                    guard indexPath.item < orderedIDs.count,
                          let cell = collectionView.cellForItem(at: indexPath) as? ProtectedNativeMediaCell,
                          let item = itemsByID[orderedIDs[indexPath.item]] else { continue }
                    cell.updateSelection(selected: parent.selectedIDs.contains(item.id), selecting: parent.isSelecting)
                }
            }
        }

        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let width = floor((collectionView.bounds.width - 3.0) / 3.0)
            return CGSize(width: width, height: width)
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard indexPath.item < orderedIDs.count,
                  let item = itemsByID[orderedIDs[indexPath.item]] else { return }
            parent.onTap(item)
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            guard indexPath.item < orderedIDs.count else { return }
            let threshold = max(0, orderedIDs.count - 30)
            guard indexPath.item >= threshold,
                  let item = itemsByID[orderedIDs[indexPath.item]],
                  lastPaginationID != item.id else { return }
            lastPaginationID = item.id
            parent.onNeedsMore(item)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let collectionView,
                  let indexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
                  indexPath.item < orderedIDs.count,
                  let item = itemsByID[orderedIDs[indexPath.item]] else { return }
            parent.onLongPress(item)
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let items = indexPaths.compactMap { path -> ProtectedCloudMedia? in
                guard path.item < orderedIDs.count else { return nil }
                return itemsByID[orderedIDs[path.item]]
            }
            pipeline.prefetch(items)
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            let ids = indexPaths.compactMap { path -> UUID? in
                guard path.item < orderedIDs.count else { return nil }
                return orderedIDs[path.item]
            }
            pipeline.cancel(ids: ids)
        }

        private func loadThumbnail(for item: ProtectedCloudMedia, into cell: ProtectedNativeMediaCell) {
            let id = item.id
            if let cached = pipeline.cachedImage(for: id) {
                cell.setImage(cached, representedID: id)
                return
            }
            pipeline.load(item) { [weak cell] image in
                guard let image else { return }
                cell?.setImage(image, representedID: id)
            }
        }

        private func isVideo(_ item: ProtectedCloudMedia) -> Bool {
            item.mediaType.lowercased().contains("video")
        }
    }
}

@MainActor
private final class ProtectedNativeMediaCell: UICollectionViewCell {
    static let reuseID = "ProtectedNativeMediaCell"

    private let imageView = UIImageView()
    private let placeholder = UIImageView()
    private let playBadge = UIImageView()
    private let selectionBadge = UIImageView()
    private(set) var representedID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.55)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        placeholder.contentMode = .center
        placeholder.tintColor = .tertiaryLabel
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(placeholder)

        playBadge.image = UIImage(systemName: "play.fill")
        playBadge.tintColor = .white
        playBadge.contentMode = .center
        playBadge.backgroundColor = UIColor.black.withAlphaComponent(0.52)
        playBadge.layer.cornerRadius = 12.5
        playBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(playBadge)

        selectionBadge.tintColor = .white
        selectionBadge.layer.shadowColor = UIColor.black.cgColor
        selectionBadge.layer.shadowOpacity = 0.5
        selectionBadge.layer.shadowRadius = 2
        selectionBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(selectionBadge)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            placeholder.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            playBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            playBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            playBadge.widthAnchor.constraint(equalToConstant: 25),
            playBadge.heightAnchor.constraint(equalToConstant: 25),
            selectionBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -7),
            selectionBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            selectionBadge.widthAnchor.constraint(equalToConstant: 24),
            selectionBadge.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedID = nil
        imageView.image = nil
        placeholder.isHidden = false
        selectionBadge.isHidden = true
    }

    func configure(id: UUID, isVideo: Bool, selected: Bool, selecting: Bool) {
        representedID = id
        imageView.image = nil
        placeholder.image = UIImage(systemName: isVideo ? "video.fill" : "photo.fill")
        placeholder.isHidden = false
        playBadge.isHidden = !isVideo
        updateSelection(selected: selected, selecting: selecting)
    }

    func updateSelection(selected: Bool, selecting: Bool) {
        selectionBadge.isHidden = !selecting
        selectionBadge.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
    }

    func setImage(_ image: UIImage, representedID: UUID) {
        guard self.representedID == representedID else { return }
        imageView.image = image
        placeholder.isHidden = true
    }
}

/// Thumbnail pipeline shared by every reusable grid cell.
/// Local PhotoKit thumbnails use PHCachingImageManager; cloud thumbnails use a
/// bounded memory cache plus an on-disk cache so revisiting a scrolled region
/// doesn't re-download it.
@MainActor
private final class ProtectedGridImagePipeline {
    static let shared = ProtectedGridImagePipeline()

    private let photoManager = PHCachingImageManager()
    private let memory = NSCache<NSString, UIImage>()
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let diskDirectory: URL
    private let targetSize = CGSize(width: 900, height: 900)

    private init() {
        memory.countLimit = 420
        memory.totalCostLimit = 96 * 1024 * 1024
        diskDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiberonsProtectedThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    func cachedImage(for id: UUID) -> UIImage? {
        if let image = memory.object(forKey: id.uuidString as NSString) { return image }
        let url = diskURL(for: id)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        storeMemory(image, id: id)
        return image
    }

    func load(_ item: ProtectedCloudMedia, completion: @escaping @MainActor (UIImage?) -> Void) {
        if let cached = cachedImage(for: item.id) { completion(cached); return }
        if tasks[item.id] != nil { return }

        if let localID = item.iosLocalIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            photoManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { [weak self] image, info in
                guard let self, let image else { return }
                Task { @MainActor in
                    self.storeMemory(image, id: item.id)
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if !degraded { self.persist(image, id: item.id) }
                    completion(image)
                }
            }
            return
        }

        tasks[item.id] = Task { [weak self] in
            guard let self else { return }
            let image = await self.fetchCloudThumbnail(item)
            guard !Task.isCancelled else { self.tasks[item.id] = nil; return }
            if let image {
                self.storeMemory(image, id: item.id)
                self.persist(image, id: item.id)
            }
            self.tasks[item.id] = nil
            completion(image)
        }
    }

    func prefetch(_ items: [ProtectedCloudMedia]) {
        var localAssets: [PHAsset] = []
        for item in items {
            if cachedImage(for: item.id) != nil { continue }
            if let localID = item.iosLocalIdentifier,
               let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject {
                localAssets.append(asset)
            } else {
                load(item) { _ in }
            }
        }
        if !localAssets.isEmpty {
            photoManager.startCachingImages(for: localAssets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
        }
    }

    func cancel(ids: [UUID]) {
        for id in ids {
            tasks[id]?.cancel()
            tasks[id] = nil
        }
    }

    private func fetchCloudThumbnail(_ item: ProtectedCloudMedia) async -> UIImage? {
        if let preview = try? await SupabaseService.cloudPreviewURL(assetID: item.id),
           let (data, response) = try? await URLSession.shared.data(from: preview),
           ((response as? HTTPURLResponse)?.statusCode ?? 500) < 300,
           let image = downsample(data, maxPixelSize: 900) {
            return image
        }

        // Photos may fall back to the protected original; videos deliberately
        // avoid downloading the whole original merely to populate the grid.
        guard !item.mediaType.lowercased().contains("video"),
              let original = try? await SupabaseService.cloudOriginalURL(assetID: item.id),
              let (data, response) = try? await URLSession.shared.data(from: original),
              ((response as? HTTPURLResponse)?.statusCode ?? 500) < 300 else { return nil }
        return downsample(data, maxPixelSize: 900)
    }

    private func storeMemory(_ image: UIImage, id: UUID) {
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        memory.setObject(image, forKey: id.uuidString as NSString, cost: cost)
    }

    private func persist(_ image: UIImage, id: UUID) {
        guard let data = image.jpegData(compressionQuality: 0.86) else { return }
        let url = diskURL(for: id)
        Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
    }

    private func diskURL(for id: UUID) -> URL {
        diskDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
    }

    private func downsample(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}