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
    @State private var previewAsset: PHAsset?
    @State private var showingPreview = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)
    private var visibleAssets: [PHAsset] { showSelectedOnly ? assets.filter { selected.contains($0.localIdentifier) } : assets }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.text("Oldest first", "Plus anciens en premier")).font(.headline)
                            Text(language.text("Tap ✓ to select. Tap the photo to open it.", "Touchez ✓ pour sélectionner. Touchez la photo pour l’ouvrir.")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !selected.isEmpty {
                            Button { withAnimation { showSelectedOnly.toggle() } } label: {
                                Text(showSelectedOnly ? language.text("Show all", "Tout voir") : "\(selected.count) ✓").font(.subheadline.bold()).padding(.horizontal, 11).padding(.vertical, 7).background(Color.accentColor.opacity(0.12), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 14).padding(.top, 6)

                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(visibleAssets, id: \.localIdentifier) { asset in
                            let isSelected = selected.contains(asset.localIdentifier)
                            ZStack(alignment: .topTrailing) {
                                Button { previewAsset = asset; showingPreview = true } label: {
                                    SelectionThumbnail(asset: asset).frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit).clipped()
                                        .overlay { if isSelected { Color.accentColor.opacity(0.12) } }
                                        .overlay { if isSelected { Rectangle().stroke(Color.accentColor, lineWidth: 3) } }
                                }.buttonStyle(.plain)
                                Button { withAnimation(.easeOut(duration: 0.12)) { toggle(asset) } } label: {
                                    ZStack { Circle().fill(isSelected ? Color.accentColor : Color.black.opacity(0.48)).frame(width: 28, height: 28); Image(systemName: isSelected ? "checkmark" : "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }.padding(7)
                                }.buttonStyle(.plain)
                                if asset.mediaType == .video { HStack { Image(systemName: "play.fill"); Text(duration(asset.duration)) }.font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 4).background(.black.opacity(0.55), in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(6).allowsHitTesting(false) }
                            }
                        }
                    }.padding(.horizontal, 3).padding(.bottom, 110)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(language.text("Choose memories", "Choisir les souvenirs"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 9) {
                    HStack { Text(selected.isEmpty ? language.text("Nothing selected", "Aucune sélection") : language.text("\(selected.count) selected", "\(selected.count) sélectionnés")).font(.subheadline.bold()); Spacer(); if !selected.isEmpty { Button(language.text("Clear", "Effacer")) { selected.removeAll(); showSelectedOnly = false }.font(.subheadline) } }
                    Button { let ids = assets.filter { selected.contains($0.localIdentifier) }.map(\.localIdentifier); dismiss(); Task { await backup.backup(localIdentifiers: ids) } } label: { Label(language.text("Protect selected memories", "Protéger les souvenirs sélectionnés"), systemImage: "icloud.and.arrow.up.fill").fontWeight(.semibold).frame(maxWidth: .infinity).frame(height: 48) }.buttonStyle(.borderedProminent).controlSize(.large).disabled(selected.isEmpty || backup.isRunning)
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6).background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(language.text("Cancel", "Annuler")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Menu { Button(language.text("Select all", "Tout sélectionner")) { selected = Set(assets.map(\.localIdentifier)); showSelectedOnly = false }; if !selected.isEmpty { Button(language.text("Clear selection", "Effacer la sélection"), role: .destructive) { selected.removeAll(); showSelectedOnly = false } } } label: { Image(systemName: "ellipsis.circle") } }
            }
            .fullScreenCover(isPresented: $showingPreview, onDismiss: { previewAsset = nil }) {
                if let asset = previewAsset { MediaPreviewView(asset: asset, selected: $selected, language: language) }
            }
            .task { loadOldest() }
        }
    }

    private func loadOldest() { let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]; let result = PHAsset.fetchAssets(with: options); var loaded: [PHAsset] = []; result.enumerateObjects { asset, _, _ in loaded.append(asset) }; assets = loaded }
    private func toggle(_ asset: PHAsset) { if selected.contains(asset.localIdentifier) { selected.remove(asset.localIdentifier) } else { selected.insert(asset.localIdentifier) } }
    private func duration(_ value: TimeInterval) -> String { let total = Int(value.rounded()); return String(format: "%d:%02d", total / 60, total % 60) }
}

private struct MediaPreviewView: View {
    let asset: PHAsset
    @Binding var selected: Set<String>
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    private var isSelected: Bool { selected.contains(asset.localIdentifier) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView().tint(.white) }
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).foregroundStyle(.white).frame(width: 42, height: 42).background(.black.opacity(0.5), in: Circle()) }
                    Spacer()
                    Button { if isSelected { selected.remove(asset.localIdentifier) } else { selected.insert(asset.localIdentifier) } } label: { Label(isSelected ? language.text("Selected", "Sélectionné") : language.text("Select", "Sélectionner"), systemImage: isSelected ? "checkmark.circle.fill" : "circle").font(.subheadline.bold()).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 42).background(isSelected ? Color.accentColor : Color.black.opacity(0.5), in: Capsule()) }
                }.padding()
                Spacer()
                if let date = asset.creationDate { Text(date.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.5), in: Capsule()).padding(.bottom, 16) }
            }
        }
        .task { let options = PHImageRequestOptions(); options.deliveryMode = .highQualityFormat; options.resizeMode = .none; options.isNetworkAccessAllowed = true; PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { value, _ in if let value { Task { @MainActor in image = value } } } }
    }
}

private struct SelectionThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    var body: some View { ZStack { Rectangle().fill(Color.secondary.opacity(0.10)); if let image { Image(uiImage: image).resizable().scaledToFill() } else { ProgressView() } }.clipped().task(id: asset.localIdentifier) { let scale = UIScreen.main.scale; let side = 150 * scale; let options = PHImageRequestOptions(); options.deliveryMode = .opportunistic; options.resizeMode = .fast; options.isNetworkAccessAllowed = true; PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options) { value, _ in if let value { Task { @MainActor in image = value } } } } }
}
