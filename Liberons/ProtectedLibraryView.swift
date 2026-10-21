import SwiftUI
import Photos
import AVKit
import AVFoundation

private enum ProtectedLibraryFilter: String, CaseIterable, Identifiable {
    case all, photos, videos
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .photos: return "photo.fill"
        case .videos: return "play.rectangle.fill"
        }
    }
    func title(_ language: LanguageStore) -> String {
        switch self {
        case .all: return language.text("All", "Tout")
        case .photos: return "Photos"
        case .videos: return language.text("Videos", "Vidéos")
        }
    }
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
                else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7, pinnedViews: []) {
                            if billing.isPaymentGrace { BillingLibraryNotice(language: language, restricted: false, days: billing.graceDaysRemaining) }
                            else if billing.isPaymentRestricted { BillingLibraryNotice(language: language, restricted: true, days: 0) }

                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .frame(width: 27, height: 27)
                                    .background(Color.green.opacity(0.09), in: Circle())
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(language.text("Protected memories", "Souvenirs protégés"))
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(filterCounts[.all, default: store.items.count].formatted()) \(language.text("items secured in Libérons", "éléments sécurisés dans Libérons"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 6)
                                Menu {
                                    Button { setSort(newestFirst: true) } label: { Label(language.text("Newest first", "Plus récents"), systemImage: sortNewestFirst ? "checkmark" : "arrow.down") }
                                    Button { setSort(newestFirst: false) } label: { Label(language.text("Oldest first", "Plus anciens"), systemImage: !sortNewestFirst ? "checkmark" : "arrow.up") }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(sortNewestFirst ? language.text("Recent", "Récents") : language.text("Oldest", "Anciens"))
                                            .font(.caption.weight(.semibold))
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(.secondary.opacity(0.08), in: Capsule())
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 1)

                            HStack(spacing: 4) {
                                ForEach(ProtectedLibraryFilter.allCases) { filter in
                                    Button { selectFilter(filter) } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: filter.icon).font(.caption.weight(.semibold))
                                            Text(filter.title(language)).font(.subheadline.weight(.semibold))
                                        }
                                        .foregroundStyle(mediaFilter == filter ? Color.primary : Color.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background {
                                            if mediaFilter == filter {
                                                Capsule().fill(Color(uiColor: .systemBackground)).shadow(color: .black.opacity(0.08), radius: 5, y: 2).matchedGeometryEffect(id: "activeFilter", in: filterTransition)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(2.5)
                            .background(Color.secondary.opacity(0.09), in: Capsule())
                            .padding(.horizontal, 16)

                            if isSelecting {
                                Text("\(selectedIDs.count) \(language.text("selected", "sélectionné(s)"))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 1)
                            }

                            if displayItems.isEmpty {
                                ContentUnavailableView(language.text("Nothing here yet", "Rien ici pour le moment"), systemImage: mediaFilter.icon, description: Text(language.text("Protected media in this category will appear here.", "Les médias protégés de cette catégorie apparaîtront ici."))).frame(maxWidth: .infinity).padding(.vertical, 42)
                            } else {
                                LazyVGrid(columns: columns, spacing: 1.5) {
                                    ForEach(displayItems) { item in
                                        ProtectedLibraryTile(item: item).matchedTransitionSource(id: item.id, in: photoTransition)
                                            .overlay(alignment: .topTrailing) { if isSelecting { Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(.white).shadow(radius: 3).padding(7) } }
                                            .contentShape(Rectangle()).onTapGesture { isSelecting ? toggle(item.id) : (viewerItem = item) }.onLongPressGesture(minimumDuration: 0.35) { if !isSelecting { isSelecting = true; selectedIDs = [item.id] } }
                                    }
                                }
                            }
                        }.padding(.bottom, 132)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .refreshable { await refreshLibrary() }
                }
            }
            .navigationTitle(isSelecting ? language.text("Select", "Sélection") : language.text("Library", "Bibliothèque"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { if !store.items.isEmpty { Button(isSelecting ? language.text("Done", "OK") : language.text("Select", "Sélectionner")) { isSelecting.toggle(); if !isSelecting { selectedIDs.removeAll() } } } } }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting {
                    HStack(spacing: 12) {
                        Button {
                            let visible = Set(displayItems.map(\.id))
                            if !visible.isEmpty && selectedIDs == visible { selectedIDs.removeAll() } else { selectedIDs = visible }
                        } label: {
                            let visible = Set(displayItems.map(\.id))
                            Text(!visible.isEmpty && selectedIDs == visible ? language.text("Deselect all", "Tout désélectionner") : language.text("Select all", "Tout sélectionner")).font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        Button(role: .destructive) { showBulkDelete = true } label: {
                            if deletingSelection { ProgressView() } else { Label(language.text("Delete from Libérons", "Supprimer de Libérons"), systemImage: "trash").font(.subheadline.weight(.semibold)) }
                        }.disabled(selectedIDs.isEmpty || deletingSelection)
                    }.padding(.horizontal, 18).padding(.vertical, 12).background(.ultraThinMaterial)
                }
            }
            .task { await refreshLibrary() }
            .fullScreenCover(item: $viewerItem) { item in ProtectedGalleryViewer(items: displayItems, initialID: item.id, language: language, billing: billing).navigationTransition(.zoom(sourceID: item.id, in: photoTransition)).onDisappear { Task { await refreshLibrary() } } }
            .sheet(isPresented:$showBulkDelete){VStack(spacing:0){Capsule().fill(.secondary.opacity(0.35)).frame(width:38,height:5).padding(.top,10);VStack(spacing:18){Image(systemName:"trash.fill").font(.system(size:28,weight:.semibold)).foregroundStyle(.red).frame(width:62,height:62).background(Color.red.opacity(0.10),in:Circle());VStack(spacing:8){Text(language.text("Delete from Libérons?","Supprimer de Libérons ?")).font(.title2.bold()).multilineTextAlignment(.center);Text(language.text("The selected protected memories will be permanently removed from Libérons Cloud.","Les souvenirs protégés sélectionnés seront supprimés définitivement de Libérons Cloud.")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)};Label(language.text("This cannot be undone.","Cette action est irréversible."),systemImage:"exclamationmark.triangle.fill").font(.footnote.bold()).foregroundStyle(.red).padding(12).frame(maxWidth:.infinity).background(Color.red.opacity(0.08),in:RoundedRectangle(cornerRadius:14));Button{showBulkDelete=false;Task{await deleteSelected()}}label:{Text(language.text("Delete permanently","Supprimer définitivement")).font(.headline).frame(maxWidth:.infinity).padding(.vertical,15).foregroundStyle(.white).background(Color.red,in:RoundedRectangle(cornerRadius:16))}.buttonStyle(.plain);Button(language.text("Cancel","Annuler")){showBulkDelete=false}.font(.headline).foregroundStyle(.primary).padding(.bottom,4)}.padding(24)}.presentationDetents([.height(410)]).presentationDragIndicator(.hidden).presentationCornerRadius(30)}
        }
    }

    private func toggle(_ id: UUID) { if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) } }

    @MainActor private func selectFilter(_ filter: ProtectedLibraryFilter) {
        guard mediaFilter != filter else { return }
        withAnimation(.snappy(duration: 0.24)) { mediaFilter = filter }
        rebuildDisplayItems()
        if isSelecting { selectedIDs.formIntersection(Set(displayItems.map(\.id))) }
    }

    @MainActor private func setSort(newestFirst: Bool) {
        guard sortNewestFirst != newestFirst else { return }
        sortNewestFirst = newestFirst
        rebuildDisplayItems()
    }

    @MainActor private func rebuildDisplayItems() {
        var all = 0, photos = 0, videos = 0
        var visible: [ProtectedCloudMedia] = []
        visible.reserveCapacity(store.items.count)
        for item in store.items {
            all += 1
            let video = isVideo(item)
            if video { videos += 1 } else { photos += 1 }
            let include: Bool
            switch mediaFilter {
            case .all: include = true
            case .photos: include = !video
            case .videos: include = video
            }
            if include { visible.append(item) }
        }
        visible.sort {
            let lhs = $0.capturedAt ?? $0.createdAt
            let rhs = $1.capturedAt ?? $1.createdAt
            return sortNewestFirst ? lhs > rhs : lhs < rhs
        }
        filterCounts = [.all: all, .photos: photos, .videos: videos]
        displayItems = visible
    }

    @MainActor private func refreshLibrary() async {
        async let a: Void = store.refresh()
        async let b: Void = billing.refresh()
        _ = await (a, b)
        rebuildDisplayItems()
    }

    @MainActor private func deleteSelected() async { deletingSelection = true; for id in selectedIDs { try? await SupabaseService.deleteCloudMedia(assetID: id) }; selectedIDs.removeAll(); isSelecting = false; deletingSelection = false; await refreshLibrary() }
}

private struct BillingLibraryNotice: View {
    @ObservedObject var language:LanguageStore; let restricted:Bool; let days:Int
    var body:some View { HStack(alignment:.top,spacing:12){Image(systemName:restricted ? "lock.fill":"exclamationmark.triangle.fill").foregroundStyle(restricted ? .red:.orange).font(.title3);VStack(alignment:.leading,spacing:4){Text(restricted ? language.text("Restore access paused","Restauration suspendue") : language.text("Payment needs attention","Paiement à régulariser")).font(.subheadline.bold());Text(restricted ? language.text("Your memories remain protected and visible in Libérons. Restore to Photos is unavailable until payment is regularized.","Vos souvenirs restent protégés et visibles dans Libérons. La restauration vers Photos est indisponible jusqu’à la régularisation du paiement.") : language.text("New backups are paused. You can still restore a limited amount for about \(days) day(s).","Les nouvelles sauvegardes sont suspendues. Vous pouvez encore restaurer une quantité limitée pendant environ \(days) jour(s)." )).font(.caption).foregroundStyle(.secondary)}}.padding(14).background((restricted ? Color.red:Color.orange).opacity(0.08),in:RoundedRectangle(cornerRadius:16)).padding(.horizontal,16) }
}

private struct ProtectedGalleryViewer: View {
    let items:[ProtectedCloudMedia]; let initialID:UUID; @ObservedObject var language:LanguageStore; @ObservedObject var billing:CloudStorageSummary
    @Environment(\.dismiss) private var dismiss; @State private var selection:UUID; @State private var showInfo=false; @State private var verticalOffset:CGFloat=0
    private let indexByID:[UUID:Int]
    init(items:[ProtectedCloudMedia],initialID:UUID,language:LanguageStore,billing:CloudStorageSummary){self.items=items;self.initialID=initialID;self.language=language;self.billing=billing;self.indexByID=Dictionary(uniqueKeysWithValues:items.enumerated().map{($0.element.id,$0.offset)});_selection=State(initialValue:initialID)}
    private var currentIndex:Int?{indexByID[selection]}
    private var current:ProtectedCloudMedia?{guard let i=currentIndex,items.indices.contains(i) else{return nil};return items[i]}
    var body: some View { ZStack{Color.black.opacity(Double(1 - min(max(verticalOffset, CGFloat.zero) / CGFloat(520), CGFloat(0.72)))).ignoresSafeArea();TabView(selection:$selection){ForEach(items){CloudPhotoPage(item:$0,language:language,billing:billing).tag($0.id)}}.tabViewStyle(.page(indexDisplayMode:.never)).ignoresSafeArea().offset(y:verticalOffset).scaleEffect(1 - min(max(verticalOffset, CGFloat.zero) / CGFloat(1800), CGFloat(0.055)));VStack{HStack{Button{dismiss()}label:{Image(systemName:"chevron.left").font(.title2.bold()).foregroundStyle(.white).frame(width:48,height:48).background(.black.opacity(0.45),in:Circle())}.buttonStyle(.plain);if let i=currentIndex{Text("\(i+1) / \(items.count)").font(.subheadline.bold()).foregroundStyle(.white).padding(8).background(.black.opacity(0.45),in:Capsule())};Spacer();Button{showInfo=true}label:{ZStack{Color.clear;Image(systemName:"ellipsis.circle.fill").font(.title2).foregroundStyle(.white)}.frame(width:56,height:56).contentShape(Rectangle())}.buttonStyle(.plain)}.padding(.horizontal,8).padding(.top,4);Spacer()}}
        .simultaneousGesture(DragGesture(minimumDistance:10).onChanged{v in guard v.translation.height>0,abs(v.translation.height)>abs(v.translation.width) else{return};verticalOffset=v.translation.height}.onEnded{v in guard v.translation.height>0,abs(v.translation.height)>abs(v.translation.width) else{withAnimation(.snappy){verticalOffset=0};return};if verticalOffset>110 || v.predictedEndTranslation.height>220{dismiss()}else{withAnimation(.snappy){verticalOffset=0}}})
        .toolbarBackground(.hidden,for:.navigationBar).toolbarColorScheme(.dark,for:.navigationBar).sheet(isPresented:$showInfo){if let current{ProtectedMediaDetail(item:current,language:language,billing:billing,closeViewer:{showInfo=false;dismiss()}).presentationDetents([.fraction(0.72),.large]).presentationDragIndicator(.visible).presentationCornerRadius(34).presentationBackground(.regularMaterial).presentationContentInteraction(.scrolls).presentationBackgroundInteraction(.enabled(upThrough:.fraction(0.72)))}}
    }
}

private struct CloudPhotoPage: View {
    let item: ProtectedCloudMedia
    @ObservedObject var language: LanguageStore
    @ObservedObject var billing: CloudStorageSummary
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var loading = true
    @State private var loadFailed = false
    @State private var playbackFile: URL?
    @State private var videoProgress: Double = 0
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }
    var body: some View {
        ZStack {
            Color.black
            if isVideo, let player { VideoPlayer(player: player).onAppear { player.play() } }
            else if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if loading { VStack(spacing:14){ProgressView().tint(.white);if isVideo{Text(language.text("Preparing protected video…","Préparation de la vidéo protégée…")).font(.footnote).foregroundStyle(.white.opacity(0.75));if videoProgress>0{ProgressView(value:videoProgress).progressViewStyle(.linear).frame(width:180).tint(.white)}}} }
            else if loadFailed { VStack(spacing:10){Image(systemName:"exclamationmark.icloud").font(.title).foregroundStyle(.white);Text(language.text("Unable to load this video.","Impossible de charger cette vidéo.")).font(.footnote).foregroundStyle(.white.opacity(0.8))} }
            else { Image(systemName:"exclamationmark.icloud").foregroundStyle(.white) }
        }.task(id:item.id){await load()}.onDisappear{player?.pause();player=nil}
    }
    @MainActor private func load() async {
        loading=true;loadFailed=false;defer{loading=false}
        if isVideo{guard !billing.isPaymentRestricted else{loadFailed=true;return};do{try await loadProtectedVideo()}catch{print("[Libérons Video] Playback failed:",item.id,error.localizedDescription);loadFailed=true};return}
        if let cached=ProtectedMediaCache.shared.image(for:item.id){image=cached;return}
        if let id=item.iosLocalIdentifier,let asset=PHAsset.fetchAssets(withLocalIdentifiers:[id],options:nil).firstObject{let options=PHImageRequestOptions();options.isNetworkAccessAllowed=true;options.deliveryMode = .opportunistic;options.resizeMode = .fast;PHImageManager.default().requestImage(for:asset,targetSize:CGSize(width:1600,height:1600),contentMode:.aspectFit,options:options){value,_ in if let value{ProtectedMediaCache.shared.store(value,for:self.item.id);Task{@MainActor in image=value}}};return}
        if let preview=try? await SupabaseService.cloudPreviewURL(assetID:item.id),let(data,response)=try? await URLSession.shared.data(from:preview),(response as? HTTPURLResponse)?.statusCode ?? 500 < 300,let decoded=UIImage(data:data){ProtectedMediaCache.shared.store(decoded,for:item.id);image=decoded;return}
        guard !billing.isPaymentRestricted else{return}
        if let original=try? await SupabaseService.cloudOriginalURL(assetID:item.id),let(data,response)=try? await URLSession.shared.data(from:original),(response as? HTTPURLResponse)?.statusCode ?? 500 < 300,let decoded=UIImage(data:data){ProtectedMediaCache.shared.store(decoded,for:item.id);image=decoded}
    }
    @MainActor private func loadProtectedVideo() async throws {
        let fm=FileManager.default;let dir=fm.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("LiberonsPlayback",isDirectory:true);try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        let filename=item.originalFilename ?? "protected-video.mov";var ext=URL(fileURLWithPath:filename).pathExtension.lowercased();if ext.isEmpty{ext="mov"};let local=dir.appendingPathComponent(item.id.uuidString).appendingPathExtension(ext)
        if fm.fileExists(atPath:local.path){playProtectedVideo(at:local);return}
        do{let request=try await SupabaseService.protectedStreamRequest(assetID:item.id);guard let url=request.url else{throw URLError(.badURL)};let options:[String:Any]=["AVURLAssetHTTPHeaderFieldsKey":request.allHTTPHeaderFields ?? [:]];let asset=AVURLAsset(url:url,options:options);let playable=try await asset.load(.isPlayable);guard playable else{throw URLError(.cannotDecodeContentData)};let playerItem=AVPlayerItem(asset:asset);playerItem.preferredForwardBufferDuration=3;let avPlayer=AVPlayer(playerItem:playerItem);avPlayer.automaticallyWaitsToMinimizeStalling=true;player=avPlayer;avPlayer.play();return}catch{print("[Libérons Video] Fast stream unavailable, using protected fallback:",item.id,error.localizedDescription)}
        let remote=try await SupabaseService.cloudStreamURL(assetID:item.id);let(downloaded,response)=try await URLSession.shared.download(from:remote);guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else{throw URLError(.badServerResponse)};let attrs=try fm.attributesOfItem(atPath:downloaded.path);let downloadedSize=(attrs[.size] as? NSNumber)?.int64Value ?? 0;guard downloadedSize>0 else{throw URLError(.zeroByteResource)};if item.sizeBytes>0 && downloadedSize != item.sizeBytes{throw NSError(domain:"LiberonsProtectedVideo",code:1001,userInfo:[NSLocalizedDescriptionKey:"Protected video download is incomplete."])};try? fm.removeItem(at:local);try fm.moveItem(at:downloaded,to:local);playProtectedVideo(at:local)
    }
    @MainActor private func playProtectedVideo(at url:URL){playbackFile=url;let playerItem=AVPlayerItem(url:url);let avPlayer=AVPlayer(playerItem:playerItem);avPlayer.automaticallyWaitsToMinimizeStalling=true;player=avPlayer;avPlayer.play()}
}

private final class ProtectedMediaCache:@unchecked Sendable{static let shared=ProtectedMediaCache();private let cache=NSCache<NSString,UIImage>();private init(){cache.countLimit=350;cache.totalCostLimit=80*1024*1024};func image(for id:UUID)->UIImage?{cache.object(forKey:id.uuidString as NSString)};func store(_ image:UIImage,for id:UUID){let cost=Int(image.size.width*image.size.height*4);cache.setObject(image,forKey:id.uuidString as NSString,cost:cost)}}
private enum ProtectedAction:Hashable{case restore,removeDevice,deleteCloud}
private struct ProtectedMediaDetail:View{
    let item:ProtectedCloudMedia;@ObservedObject var language:LanguageStore;@ObservedObject var billing:CloudStorageSummary;var closeViewer:(()->Void)?=nil
    @Environment(\.dismiss) private var dismiss;@State private var operationError:String?;@State private var deleting=false;@State private var restoring=false;@State private var localExists=false;@State private var currentLocalIdentifier:String?;@State private var restoredSuccessfully=false;@State private var pendingAction:ProtectedAction?
    private var isVideo:Bool{item.mediaType.lowercased().contains("video")}
    var body:some View{NavigationStack{ScrollView{VStack(alignment:.leading,spacing:18){HStack{VStack(alignment:.leading,spacing:4){Text(item.originalFilename ?? (isVideo ? "Video":"Photo")).font(.title3.bold());Text(isVideo ? language.text("Video","Vidéo"):"Photo").foregroundStyle(.secondary)};Spacer();Label(language.text("Protected","Protégé"),systemImage:"checkmark.shield.fill").font(.caption.bold()).foregroundStyle(.green)};if billing.isPaymentGrace{BillingLibraryNotice(language:language,restricted:false,days:billing.graceDaysRemaining).padding(.horizontal,-16)}else if billing.isPaymentRestricted{BillingLibraryNotice(language:language,restricted:true,days:0).padding(.horizontal,-16)};Divider();MetadataRow(icon:"calendar",title:isVideo ? language.text("Video taken","Vidéo prise le"):language.text("Photo taken","Photo prise le"),value:format(item.capturedAt));MetadataRow(icon:"icloud.and.arrow.up",title:language.text("Added to Libérons","Ajouté à Libérons le"),value:format(item.createdAt));MetadataRow(icon:"checkmark.shield",title:language.text("Cloud protection verified","Protection cloud vérifiée le"),value:format(item.protectedAt));MetadataRow(icon:"externaldrive",title:language.text("Original size","Taille originale"),value:ByteCountFormatter.string(fromByteCount:item.sizeBytes,countStyle:.file));MetadataRow(icon:"iphone",title:language.text("On this iPhone","Sur cet iPhone"),value:localExists ? language.text("Available on this iPhone","Disponible sur cet iPhone"):language.text("Not currently on this iPhone","Pas actuellement sur cet iPhone"));Label(language.text("Stored securely in Libérons Cloud.","Stocké de manière sécurisée dans Libérons Cloud."),systemImage:"icloud.fill").font(.footnote).foregroundStyle(.secondary);if restoredSuccessfully{Label(language.text("Restored to Photos","Restauré dans Photos"),systemImage:"checkmark.circle.fill").font(.subheadline.bold()).foregroundStyle(.green)};Divider();Text(language.text("Manage this memory","Gérer ce souvenir")).font(.headline);if !localExists{actionButton(billing.isPaymentRestricted ? language.text("Restore unavailable — payment required","Restauration indisponible — paiement requis"):language.text("Restore to Photos","Restaurer dans Photos"),icon:billing.isPaymentRestricted ? "lock.fill":"square.and.arrow.down",color:billing.isPaymentRestricted ? .secondary:.blue){if !billing.isPaymentRestricted{pendingAction = .restore}}.disabled(restoring||deleting||billing.isPaymentRestricted)};if localExists{actionButton(language.text("Remove from this iPhone","Supprimer de cet iPhone"),icon:"iphone.slash",color:.red){pendingAction = .removeDevice}.disabled(restoring||deleting)};actionButton(language.text("Delete permanently from Libérons","Supprimer définitivement de Libérons"),icon:"trash",color:.red){pendingAction = .deleteCloud}.disabled(deleting||restoring);if let operationError{Text(operationError).font(.footnote).foregroundStyle(.red)}}.padding(.horizontal,20).padding(.top,10).padding(.bottom,28)}}.navigationTitle(language.text("Memory details","Détails du souvenir")).navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.topBarTrailing){Button(language.text("Done","Fermer")){dismiss()}.fontWeight(.semibold)}}.task{currentLocalIdentifier=item.iosLocalIdentifier;refreshLocalState();await billing.refresh()}.sheet(item:Binding(get:{pendingAction.map(ActionSheetItem.init)},set:{if $0==nil{pendingAction=nil}})){wrapper in premiumSheet(for:wrapper.action)}}
    private struct ActionSheetItem:Identifiable{let action:ProtectedAction;var id:ProtectedAction{action};init(_ action:ProtectedAction){self.action=action}}
    @ViewBuilder private func premiumSheet(for action:ProtectedAction)->some View{VStack(spacing:0){Capsule().fill(.secondary.opacity(0.35)).frame(width:38,height:5).padding(.top,10);VStack(spacing:18){Image(systemName:actionIcon(action)).font(.system(size:28,weight:.semibold)).foregroundStyle(action == .restore ? .blue:.red).frame(width:62,height:62).background((action == .restore ? Color.blue:Color.red).opacity(0.10),in:Circle());VStack(spacing:8){Text(actionTitle(action)).font(.title2.bold()).multilineTextAlignment(.center);Text(actionMessage(action)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)};if action == .removeDevice{Label(language.text("Your protected cloud copy will remain in Libérons.","Votre copie protégée restera dans Libérons Cloud."),systemImage:"checkmark.shield.fill").font(.footnote.bold()).foregroundStyle(.green).padding(12).frame(maxWidth:.infinity).background(Color.green.opacity(0.08),in:RoundedRectangle(cornerRadius:14))};if action == .deleteCloud{Label(language.text("This cannot be undone.","Cette action est irréversible."),systemImage:"exclamationmark.triangle.fill").font(.footnote.bold()).foregroundStyle(.red).padding(12).frame(maxWidth:.infinity).background(Color.red.opacity(0.08),in:RoundedRectangle(cornerRadius:14))};Button{confirm(action)}label:{Text(actionButtonTitle(action)).font(.headline).frame(maxWidth:.infinity).padding(.vertical,15).foregroundStyle(.white).background(action == .restore ? Color.blue:Color.red,in:RoundedRectangle(cornerRadius:16))}.buttonStyle(.plain);Button(language.text("Cancel","Annuler")){pendingAction=nil}.font(.headline).foregroundStyle(.primary).padding(.bottom,4)}.padding(24)}.presentationDetents([.height(action == .restore ? 350:410)]).presentationDragIndicator(.hidden).presentationCornerRadius(30)}
    private func actionIcon(_ a:ProtectedAction)->String{switch a{case .restore:"square.and.arrow.down";case .removeDevice:"iphone.slash";case .deleteCloud:"trash.fill"}}
    private func actionTitle(_ a:ProtectedAction)->String{switch a{case .restore:language.text("Restore this memory?","Restaurer ce souvenir ?");case .removeDevice:language.text("Remove from this iPhone?","Supprimer de cet iPhone ?");case .deleteCloud:language.text("Delete from Libérons?","Supprimer de Libérons ?")}}
    private func actionMessage(_ a:ProtectedAction)->String{switch a{case .restore:billing.isPaymentGrace ? language.text("Your payment is in its grace period. This restoration counts toward the temporary recovery allowance.","Votre paiement est en période de grâce. Cette restauration compte dans l’enveloppe temporaire de récupération."):language.text(isVideo ? "A copy of this protected video will be added back to your Photos library.":"A copy of this protected photo will be added back to your Photos library.",isVideo ? "Une copie de cette vidéo protégée sera ajoutée à nouveau dans votre photothèque Photos.":"Une copie de cette photo protégée sera ajoutée à nouveau dans votre photothèque Photos.");case .removeDevice:language.text(isVideo ? "This video will be removed from Photos on this iPhone to free local space.":"This photo will be removed from Photos on this iPhone to free local space.",isVideo ? "Cette vidéo sera supprimée de Photos sur cet iPhone afin de libérer de l’espace local.":"Cette photo sera supprimée de Photos sur cet iPhone afin de libérer de l’espace local.");case .deleteCloud:language.text("This protected copy will be permanently removed from Libérons Cloud.","Cette copie protégée sera supprimée définitivement de Libérons Cloud.")}}
    private func actionButtonTitle(_ a:ProtectedAction)->String{switch a{case .restore:language.text("Restore to Photos","Restaurer dans Photos");case .removeDevice:language.text("Continue","Continuer");case .deleteCloud:language.text("Delete permanently","Supprimer définitivement")}}
    private func confirm(_ a:ProtectedAction){pendingAction=nil;Task{try? await Task.sleep(for:.milliseconds(250));switch a{case .restore:await restoreToPhotos();case .removeDevice:await removeFromDevice();case .deleteCloud:await deleteFromCloud()}}}
    private func actionButton(_ title:String,icon:String,color:Color,action:@escaping()->Void)->some View{Button(action:action){HStack{if restoring && icon=="square.and.arrow.down"{ProgressView()};Label(title,systemImage:icon)}.frame(maxWidth:.infinity,alignment:.leading).padding(14).background(color.opacity(0.10),in:RoundedRectangle(cornerRadius:14)).foregroundStyle(color)}}
    private func format(_ date:Date?)->String{guard let date else{return language.text("Unknown","Inconnue")};return date.formatted(date:.long,time:.shortened)}
    private func matchingLocalAsset()->PHAsset?{if let id=currentLocalIdentifier,let asset=PHAsset.fetchAssets(withLocalIdentifiers:[id],options:nil).firstObject{return asset};let options=PHFetchOptions();if let date=item.capturedAt{options.predicate=NSPredicate(format:"creationDate >= %@ AND creationDate <= %@",date.addingTimeInterval(-2) as NSDate,date.addingTimeInterval(2) as NSDate)};let result=PHAsset.fetchAssets(with:isVideo ? .video:.image,options:options);guard result.count>0 else{return nil};if let filename=item.originalFilename{var match:PHAsset?;result.enumerateObjects{asset,_,stop in if PHAssetResource.assetResources(for:asset).contains(where:{$0.originalFilename.caseInsensitiveCompare(filename) == .orderedSame}){match=asset;stop.pointee=true}};if let match{return match}};return result.firstObject}
    private func refreshLocalState(){if let asset=matchingLocalAsset(){currentLocalIdentifier=asset.localIdentifier;localExists=true}else{localExists=false}}
    @MainActor private func restoreToPhotos()async{guard !billing.isPaymentRestricted else{operationError=language.text("Payment must be regularized before restoring originals to Photos.","Le paiement doit être régularisé avant de restaurer des originaux dans Photos.");return};restoring=true;operationError=nil;restoredSuccessfully=false;let assetID=item.id;let filename=item.originalFilename;let captured=item.capturedAt;let video=isVideo;Task.detached(priority:.userInitiated){do{let remote=try await SupabaseService.cloudOriginalURL(assetID:assetID);let ext=filename.flatMap{let e=URL(fileURLWithPath:$0).pathExtension;return e.isEmpty ? nil:e} ?? (video ? "mov":"jpg");let dir=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("LiberonsRecovery",isDirectory:true);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);let local=dir.appendingPathComponent("\(assetID.uuidString).\(ext)");if !FileManager.default.fileExists(atPath:local.path){let(downloaded,response)=try await URLSession.shared.download(from:remote);guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else{throw URLError(.badServerResponse)};try? FileManager.default.removeItem(at:local);try FileManager.default.moveItem(at:downloaded,to:local)};var newIdentifier:String?;try await PHPhotoLibrary.shared().performChanges{let request=PHAssetCreationRequest.forAsset();request.creationDate=captured;let options=PHAssetResourceCreationOptions();options.originalFilename=filename;request.addResource(with:video ? .video:.photo,fileURL:local,options:options);newIdentifier=request.placeholderForCreatedAsset?.localIdentifier};guard let newIdentifier else{throw NSError(domain:"LiberonsRestore",code:2)};try? await SupabaseService.updateLocalIdentifier(assetID:assetID,localIdentifier:newIdentifier);try? FileManager.default.removeItem(at:local);await MainActor.run{currentLocalIdentifier=newIdentifier;localExists=true;restoredSuccessfully=true;restoring=false}}catch{await MainActor.run{restoring=false;operationError=language.text(video ? "Unable to restore this video.":"Unable to restore this photo.",video ? "Impossible de restaurer cette vidéo.":"Impossible de restaurer cette photo.");refreshLocalState()}}}}
    @MainActor private func removeFromDevice()async{operationError=nil;refreshLocalState();guard let asset=matchingLocalAsset() else{localExists=false;operationError=language.text("This memory is no longer in Photos on this iPhone.","Ce souvenir n’est plus présent dans Photos sur cet iPhone.");return};do{try await PHPhotoLibrary.shared().performChanges{PHAssetChangeRequest.deleteAssets([asset] as NSArray)};localExists=false;restoredSuccessfully=false;currentLocalIdentifier=nil}catch let error as NSError{if error.domain=="PHPhotosErrorDomain" && error.code==3072{return};operationError=error.localizedDescription}}
    @MainActor private func deleteFromCloud()async{deleting=true;operationError=nil;do{_=try await SupabaseService.deleteCloudMedia(assetID:item.id);deleting=false;dismiss();closeViewer?()}catch{deleting=false;operationError=error.localizedDescription}}
}
private struct MetadataRow:View{let icon:String;let title:String;let value:String;var body:some View{HStack(alignment:.top,spacing:13){Image(systemName:icon).frame(width:24).foregroundStyle(.blue);VStack(alignment:.leading,spacing:3){Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.subheadline.bold())};Spacer()}}}
private struct ProtectedLibraryTile:View{let item:ProtectedCloudMedia;@State private var image:UIImage?;private var isVideo:Bool{item.mediaType.lowercased().contains("video")};var body:some View{ZStack{GeometryReader{proxy in ZStack{Rectangle().fill(Color.secondary.opacity(0.08));if let image{Image(uiImage:image).resizable().scaledToFill().frame(width:proxy.size.width,height:proxy.size.height).clipped()}else{Image(systemName:isVideo ? "video.fill":"photo.fill").font(.system(size:18,weight:.medium)).foregroundStyle(.tertiary)}}}.aspectRatio(1,contentMode:.fit);if isVideo{VStack{Spacer();HStack{Image(systemName:"play.fill").font(.system(size:10,weight:.bold)).foregroundStyle(.white).frame(width:25,height:25).background(.black.opacity(0.52),in:Circle()).padding(6);Spacer()}}}}.task(id:item.id){await loadThumbnail()}};@MainActor private func loadThumbnail()async{if let cached=ProtectedMediaCache.shared.image(for:item.id){image=cached;return};if let id=item.iosLocalIdentifier,let asset=PHAsset.fetchAssets(withLocalIdentifiers:[id],options:nil).firstObject{let options=PHImageRequestOptions();options.isNetworkAccessAllowed=true;PHImageManager.default().requestImage(for:asset,targetSize:CGSize(width:500,height:500),contentMode:.aspectFill,options:options){value,_ in if let value{ProtectedMediaCache.shared.store(value,for:self.item.id);Task{@MainActor in image=value}}};return};if let preview=try? await SupabaseService.cloudPreviewURL(assetID:item.id),let(data,response)=try? await URLSession.shared.data(from:preview),(response as? HTTPURLResponse)?.statusCode ?? 500 < 300,let decoded=UIImage(data:data){ProtectedMediaCache.shared.store(decoded,for:item.id);image=decoded;return};if isVideo{if let url=try? await SupabaseService.cloudOriginalURL(assetID:item.id){let asset=AVURLAsset(url:url);let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true;if let cg=try? await generator.image(at:.zero).image{image=UIImage(cgImage:cg)}};return};if let url=try? await SupabaseService.cloudOriginalURL(assetID:item.id),let(data,response)=try? await URLSession.shared.data(from:url),(response as? HTTPURLResponse)?.statusCode ?? 500 < 300{image=UIImage(data:data)}}}