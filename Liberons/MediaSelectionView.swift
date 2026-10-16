import SwiftUI
import Photos
import UIKit

struct MediaSelectionView: View {
    @ObservedObject var backup: BackupEngine
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var selected = Set<String>()
    @State private var showSelectedOnly = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private var visibleAssets: [PHAsset] { showSelectedOnly ? assets.filter { selected.contains($0.localIdentifier) } : assets }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(language.text("Oldest first", "Plus anciens en premier")).font(.headline)
                                Text(language.text("Tap a memory to select it", "Touchez un souvenir pour le sélectionner")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !selected.isEmpty {
                                Button { withAnimation(.snappy) { showSelectedOnly.toggle() } } label: {
                                    Label(showSelectedOnly ? language.text("All", "Tous") : "\(selected.count)", systemImage: showSelectedOnly ? "photo.stack" : "checkmark.circle.fill")
                                        .font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 16).padding(.top, 8)

                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(visibleAssets, id: \.localIdentifier) { asset in
                                let isSelected = selected.contains(asset.localIdentifier)
                                Button { withAnimation(.easeOut(duration: 0.15)) { toggle(asset) } } label: {
                                    ZStack {
                                        SelectionThumbnail(asset: asset)
                                            .aspectRatio(1, contentMode: .fill).clipped()
                                            .overlay { if isSelected { Color.accentColor.opacity(0.16) } }

                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(Color.accentColor, lineWidth: 4)
                                        }

                                        VStack {
                                            HStack {
                                                Spacer()
                                                ZStack {
                                                    Circle().fill(isSelected ? Color.accentColor : Color.black.opacity(0.38)).frame(width: 29, height: 29)
                                                    Image(systemName: isSelected ? "checkmark" : "circle")
                                                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                                }
                                            }
                                            Spacer()
                                            HStack {
                                                if asset.mediaType == .video {
                                                    Label(duration(asset.duration), systemImage: "play.fill")
                                                        .font(.caption2.bold()).foregroundStyle(.white)
                                                        .padding(.horizontal, 7).padding(.vertical, 5)
                                                        .background(.black.opacity(0.48), in: Capsule())
                                                }
                                                Spacer()
                                            }
                                        }.padding(8)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .shadow(color: .black.opacity(isSelected ? 0.10 : 0.035), radius: 7, y: 3)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 12).padding(.bottom, 145)
                    }
                }
            }
            .navigationTitle(language.text("Choose memories", "Choisir les souvenirs"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    HStack {
                        Text(selected.isEmpty ? language.text("Nothing selected", "Aucune sélection") : language.text("\(selected.count) selected", "\(selected.count) sélectionnés"))
                            .font(.subheadline.bold())
                        Spacer()
                        if !selected.isEmpty { Button(language.text("Clear", "Effacer")) { withAnimation { selected.removeAll(); showSelectedOnly = false } }.font(.subheadline) }
                    }
                    Button {
                        let ids = assets.filter { selected.contains($0.localIdentifier) }.map(\.localIdentifier)
                        dismiss(); Task { await backup.backup(localIdentifiers: ids) }
                    } label: {
                        HStack { Image(systemName: "icloud.and.arrow.up.fill"); Text(language.text("Protect selected memories", "Protéger les souvenirs sélectionnés")).fontWeight(.semibold) }
                            .frame(maxWidth: .infinity).frame(height: 52)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(selected.isEmpty || backup.isRunning)
                }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8).background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(language.text("Cancel", "Annuler")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(language.text("Select all", "Tout sélectionner")) { selected = Set(assets.map(\.localIdentifier)); showSelectedOnly = false }
                        if !selected.isEmpty { Button(language.text("Clear selection", "Effacer la sélection"), role: .destructive) { selected.removeAll(); showSelectedOnly = false } }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .task { loadOldest() }
        }
    }

    private func loadOldest() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var loaded: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in loaded.append(asset) }
        assets = loaded
    }

    private func toggle(_ asset: PHAsset) {
        if selected.contains(asset.localIdentifier) { selected.remove(asset.localIdentifier) }
        else { selected.insert(asset.localIdentifier) }
    }

    private func duration(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct SelectionThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.10))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { ProgressView() }
        }
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
