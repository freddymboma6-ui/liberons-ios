import SwiftUI
import Photos

struct StorageAnalysisView: View {
    @ObservedObject var language: LanguageStore
    @StateObject private var intelligence = StorageIntelligence()
    @State private var selectedCategory: StorageInsightItem.Kind?

    private var usedBytes: Int64 { max(0, intelligence.deviceCapacityBytes - intelligence.deviceAvailableBytes) }
    private var usedFraction: Double {
        guard intelligence.deviceCapacityBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(intelligence.deviceCapacityBytes))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(language.text("Storage analysis", "Analyse du stockage"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(language.text("See what is taking space and find the biggest opportunities to free your iPhone.", "Voyez ce qui prend de la place et trouvez les meilleures possibilités pour libérer votre iPhone."))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(language.text("This iPhone", "Cet iPhone"), systemImage: "iphone")
                            .font(.headline)
                        Spacer()
                        Text(size(intelligence.deviceCapacityBytes)).fontWeight(.bold)
                    }
                    ProgressView(value: usedFraction).tint(.blue)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(language.text("Used", "Utilisé")).font(.caption).foregroundStyle(.secondary)
                            Text(size(usedBytes)).font(.title3.bold())
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(language.text("Available", "Disponible")).font(.caption).foregroundStyle(.secondary)
                            Text(size(intelligence.deviceAvailableBytes)).font(.title3.bold()).foregroundStyle(.green)
                        }
                    }
                }.storageAnalysisCard()

                VStack(alignment: .leading, spacing: 10) {
                    Label(language.text("Potential space to recover", "Espace potentiellement récupérable"), systemImage: "sparkles")
                        .font(.headline).foregroundStyle(.green)
                    Text(size(intelligence.recoverableBytes))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    if intelligence.deviceCapacityBytes > 0 {
                        Text(language.text("Available space could rise from \(size(intelligence.deviceAvailableBytes)) to about \(size(intelligence.projectedAvailableBytes)). Final iOS storage can differ because of system caches.", "L’espace disponible pourrait passer de \(size(intelligence.deviceAvailableBytes)) à environ \(size(intelligence.projectedAvailableBytes)). Le stockage final d’iOS peut varier à cause des caches système."))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.storageAnalysisCard()

                if intelligence.isScanning {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(language.text("Analyzing your photo library…", "Analyse de votre photothèque…"))
                            .foregroundStyle(.secondary)
                    }.storageAnalysisCard()
                } else if intelligence.categories.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(language.text("Ready to analyze", "Prêt à analyser"), systemImage: "chart.bar.doc.horizontal")
                            .font(.headline)
                        Text(language.text("Analysis stays on this iPhone. Your photos and videos are not uploaded just to calculate these results.", "L’analyse reste sur cet iPhone. Vos photos et vidéos ne sont pas envoyées dans le cloud uniquement pour calculer ces résultats."))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button {
                            Task { await intelligence.scan() }
                        } label: {
                            Label(language.text("Analyze storage", "Analyser le stockage"), systemImage: "sparkles")
                                .frame(maxWidth: .infinity).frame(height: 42)
                        }.buttonStyle(.borderedProminent)
                    }.storageAnalysisCard()
                } else {
                    Text(language.text("What takes space", "Ce qui prend de la place")).font(.title2.bold())
                    VStack(spacing: 0) {
                        ForEach(Array(intelligence.categories.enumerated()), id: \.element.id) { index, category in
                            Button { selectedCategory = category.kind } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: icon(category.kind))
                                        .font(.system(size: 18, weight: .semibold))
                                        .frame(width: 38, height: 38)
                                        .background(Color.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(title(category.kind)).fontWeight(.semibold).foregroundStyle(.primary)
                                        Text("\(category.count.formatted()) " + language.text("items", "éléments"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(size(category.bytes)).fontWeight(.bold).foregroundStyle(.primary)
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                                }.padding(.vertical, 13)
                            }.buttonStyle(.plain)
                            if index < intelligence.categories.count - 1 { Divider().padding(.leading, 51) }
                        }
                    }.padding(.horizontal, 16).storageAnalysisCard(padding: 0)

                    if !intelligence.largestItems.isEmpty {
                        HStack {
                            Text(language.text("Largest files", "Fichiers les plus lourds")).font(.title2.bold())
                            Spacer()
                            Text(language.text("Top 50", "Top 50")).font(.caption.bold()).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(intelligence.largestItems.prefix(10).enumerated()), id: \.element.id) { index, item in
                                InsightItemRow(item: item, language: language)
                                if index < min(10, intelligence.largestItems.count) - 1 { Divider().padding(.leading, 51) }
                            }
                        }.padding(.horizontal, 16).storageAnalysisCard(padding: 0)
                    }

                    Button { Task { await intelligence.scan() } } label: {
                        Label(language.text("Analyze again", "Analyser à nouveau"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity).frame(height: 42)
                    }.buttonStyle(.bordered)
                }
            }.padding(20).padding(.bottom, 80)
        }
        .background(LiberonsTheme.canvas)
        .navigationTitle(language.text("Storage", "Stockage"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            intelligence.refreshDeviceStorage()
            if intelligence.categories.isEmpty { await intelligence.scan() }
        }
        .sheet(item: Binding(get: { selectedCategory.map(CategorySelection.init) }, set: { selectedCategory = $0?.kind })) { selection in
            NavigationStack {
                List(intelligence.items(for: selection.kind)) { item in
                    InsightItemRow(item: item, language: language)
                }
                .navigationTitle(title(selection.kind))
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDragIndicator(.visible)
        }
    }

    private func size(_ bytes: Int64) -> String {
        bytes <= 0 ? language.text("0 KB", "0 Ko") : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    private func title(_ kind: StorageInsightItem.Kind) -> String {
        switch kind {
        case .screenshot: return language.text("Screenshots", "Captures d’écran")
        case .video: return language.text("Videos", "Vidéos")
        case .largeVideo: return language.text("Large videos", "Vidéos volumineuses")
        case .longVideo: return language.text("Long videos", "Vidéos longues")
        case .slowMotion: return language.text("Slow motion", "Ralenti")
        case .timeLapse: return "Time-lapse"
        case .livePhoto: return "Live Photos"
        case .rawPhoto: return "RAW"
        case .video4K: return language.text("4K videos", "Vidéos 4K")
        case .other: return language.text("Other large files", "Autres fichiers volumineux")
        }
    }
    private func icon(_ kind: StorageInsightItem.Kind) -> String {
        switch kind {
        case .screenshot: return "iphone.gen3"
        case .video, .largeVideo, .longVideo, .video4K: return "video.fill"
        case .slowMotion: return "slowmo"
        case .timeLapse: return "timelapse"
        case .livePhoto: return "livephoto"
        case .rawPhoto: return "camera.aperture"
        case .other: return "doc.fill"
        }
    }
}

private struct CategorySelection: Identifiable {
    let kind: StorageInsightItem.Kind
    var id: StorageInsightItem.Kind { kind }
}

private struct InsightItemRow: View {
    let item: StorageInsightItem
    @ObservedObject var language: LanguageStore
    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(Color.secondary.opacity(0.10)).frame(width: 38, height: 38)
                Image(systemName: item.duration > 0 ? "play.fill" : "photo.fill").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.duration > 0 ? language.text("Video", "Vidéo") : language.text("Photo", "Photo")).fontWeight(.semibold)
                HStack(spacing: 6) {
                    if item.duration > 0 { Text(duration(item.duration)) }
                    Text("\(item.pixelWidth)×\(item.pixelHeight)")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)).fontWeight(.bold)
        }.padding(.vertical, 11)
    }
    private func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}

private extension View {
    func storageAnalysisCard(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: 14, y: 5)
    }
}
