import SwiftUI
import Photos
import AVKit

struct StorageAnalysisView: View {
    @ObservedObject var language: LanguageStore
    @ObservedObject var backup: BackupEngine
    @StateObject private var intelligence = StorageIntelligence()
    @StateObject private var cleaner = ProtectedSpaceCleaner()
    @State private var selectedCategory: StorageInsightItem.Kind?
    @State private var selectedIDs = Set<String>()
    @State private var showLargest = false
    @State private var showFreeOffer = false
    @State private var preview: AssetPreviewSelection?

    private var usedBytes:Int64{max(0,intelligence.deviceCapacityBytes-intelligence.deviceAvailableBytes)}
    private var usedFraction:Double{intelligence.deviceCapacityBytes>0 ? min(1,Double(usedBytes)/Double(intelligence.deviceCapacityBytes)):0}
    private var selectedBytes:Int64{(intelligence.items+intelligence.duplicateItems).reduce(0){$0+(selectedIDs.contains($1.id) ? $1.bytes:0)}}
    private var freeSize:String{size(cleaner.selectedBytes)}

    var body: some View {
        ScrollView{VStack(alignment:.leading,spacing:18){
            Text(language.text("Storage analysis","Analyse du stockage")).font(.system(size:34,weight:.bold,design:.rounded))
            Text(language.text("See what uses your space and choose what you want to protect.","Voyez ce qui prend votre espace et choisissez ce que vous voulez protéger.")).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:14){HStack{Label(language.text("This iPhone","Cet iPhone"),systemImage:"iphone").font(.headline);Spacer();Text(size(intelligence.deviceCapacityBytes)).fontWeight(.bold)};ProgressView(value:usedFraction).tint(.blue);HStack{VStack(alignment:.leading,spacing:3){Text(language.text("Used","Utilisé")).font(.caption).foregroundStyle(.secondary);Text(size(usedBytes)).font(.title3.bold())};Spacer();VStack(alignment:.trailing,spacing:3){Text(language.text("Available","Disponible")).font(.caption).foregroundStyle(.secondary);Text(size(intelligence.deviceAvailableBytes)).font(.title3.bold()).foregroundStyle(.green)}}}.storageAnalysisCard()
            VStack(alignment:.leading,spacing:10){Label(language.text("Space you could free","Espace que vous pourriez libérer"),systemImage:"internaldrive").font(.headline).foregroundStyle(.green);Text(size(intelligence.recoverableBytes)).font(.system(size:44,weight:.bold,design:.rounded));if intelligence.deviceCapacityBytes>0{Text(language.text("You have \(size(intelligence.deviceAvailableBytes)) available now. After protecting and removing these items, you could have up to \(size(intelligence.projectedAvailableBytes)) available.","Vous avez actuellement \(size(intelligence.deviceAvailableBytes)) disponibles. Après avoir protégé et retiré ces éléments, vous pourriez avoir jusqu’à \(size(intelligence.projectedAvailableBytes)) disponibles.")).font(.subheadline).foregroundStyle(.secondary)}}.storageAnalysisCard()
            if intelligence.isScanning && intelligence.categories.isEmpty{HStack(spacing:12){ProgressView();Text(language.text("Analyzing your photos and videos…","Analyse de vos photos et vidéos…")).foregroundStyle(.secondary)}.storageAnalysisCard()}
            else if intelligence.categories.isEmpty{VStack(alignment:.leading,spacing:12){Text(language.text("Ready to analyze","Prêt à analyser")).font(.headline);Text(language.text("Libérons checks your photos and videos on this iPhone to show what takes the most space.","Libérons vérifie vos photos et vidéos sur cet iPhone pour vous montrer ce qui prend le plus de place.")).font(.subheadline).foregroundStyle(.secondary);Button{Task{await intelligence.scan()}}label:{Text(language.text("Analyze storage","Analyser le stockage")).frame(maxWidth:.infinity).frame(height:42)}.buttonStyle(.borderedProminent)}.storageAnalysisCard()}
            else{
                if intelligence.isScanning{HStack(spacing:8){ProgressView().controlSize(.small);Text(language.text("Updating in background…","Mise à jour en arrière-plan…")).font(.caption).foregroundStyle(.secondary)}}
                Text(language.text("What takes space","Ce qui prend de la place")).font(.title2.bold())
                VStack(spacing:0){ForEach(Array(intelligence.categories.enumerated()),id:\.element.id){index,category in Button{selectedCategory=category.kind}label:{HStack(spacing:13){Image(systemName:icon(category.kind)).font(.system(size:18,weight:.semibold)).frame(width:38,height:38).background(Color.blue.opacity(0.11),in:RoundedRectangle(cornerRadius:11));VStack(alignment:.leading,spacing:3){Text(title(category.kind)).fontWeight(.semibold).foregroundStyle(.primary);Text(category.kind == .duplicate ? language.text("\(category.count.formatted()) extra copies","\(category.count.formatted()) copies en trop") : "\(category.count.formatted()) "+language.text("items","éléments")).font(.caption).foregroundStyle(.secondary)};Spacer();Text(size(category.bytes)).fontWeight(.bold).foregroundStyle(category.kind == .duplicate ? .green:.primary);Image(systemName:"chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)}.padding(.vertical,13)}.buttonStyle(.plain);if index<intelligence.categories.count-1{Divider().padding(.leading,51)}}}.padding(.horizontal,16).storageAnalysisCard(padding:0)
                if !intelligence.largestItems.isEmpty{Button{showLargest=true}label:{HStack{VStack(alignment:.leading,spacing:4){Text(language.text("Largest files","Fichiers les plus lourds")).font(.title2.bold()).foregroundStyle(.primary);Text(language.text("See the 50 largest photos and videos","Voir les 50 photos et vidéos les plus lourdes")).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.right").foregroundStyle(.secondary)}}.buttonStyle(.plain).storageAnalysisCard()}
                Button{Task{await intelligence.scan()}}label:{Text(language.text("Analyze again","Analyser à nouveau")).frame(maxWidth:.infinity).frame(height:42)}.buttonStyle(.bordered)
            }
        }.padding(20).padding(.bottom,80)}
        .background(LiberonsTheme.canvas).navigationTitle(language.text("Storage","Stockage")).navigationBarTitleDisplayMode(.inline)
        .task{await intelligence.refreshInBackgroundIfNeeded()}
        .sheet(item:Binding(get:{selectedCategory.map(CategorySelection.init)},set:{selectedCategory=$0?.kind})){selection in selectionSheet(title(selection.kind),items:intelligence.items(for:selection.kind))}
        .sheet(isPresented:$showLargest){selectionSheet(language.text("Largest files","Fichiers les plus lourds"),items:intelligence.largestItems)}
        .sheet(isPresented:$showFreeOffer){freeSpaceOffer}
    }

    @ViewBuilder private func selectionSheet(_ title:String,items:[StorageInsightItem])->some View{
        let itemIDs=Set(items.map(\.id));let allSelected = !items.isEmpty && itemIDs.isSubset(of:selectedIDs)
        NavigationStack{VStack(spacing:0){List(items){item in HStack(spacing:12){Button{toggle(item.id)}label:{Image(systemName:selectedIDs.contains(item.id) ? "checkmark.circle.fill":"circle").font(.title3).foregroundStyle(selectedIDs.contains(item.id) ? .blue:.secondary)}.buttonStyle(.plain);Button{preview=AssetPreviewSelection(items:items,startID:item.id)}label:{HStack(spacing:12){AssetThumbnail(localIdentifier:item.id,isVideo:item.duration>0);VStack(alignment:.leading,spacing:3){Text(itemLabel(item)).fontWeight(.semibold).foregroundStyle(.primary);HStack(spacing:6){if item.duration>0{Text(duration(item.duration))};Text(size(item.bytes))}.font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)}}.buttonStyle(.plain)}.contentShape(Rectangle())}.listStyle(.plain);if !selectedIDs.isEmpty{VStack(spacing:9){HStack{Text("\(selectedIDs.count) "+language.text("selected","sélectionné(s)"));Spacer();Text(size(selectedBytes)).fontWeight(.bold)};Button{let ids=Array(selectedIDs);Task{await backup.backup(localIdentifiers:ids);let protected=backup.newlyProtectedLocalIdentifiers;selectedIDs.subtract(protected);guard !protected.isEmpty else{return};await cleaner.prepareExact(localIdentifiers:protected);if !cleaner.selectedLocalIdentifiers.isEmpty{showFreeOffer=true}}}label:{HStack{if backup.isRunning{ProgressView().tint(.white)};Text(backup.isRunning ? language.text("Protecting…","Protection…"):language.text("Protect selected with Libérons","Protéger la sélection avec Libérons"))}.frame(maxWidth:.infinity).frame(height:44)}.buttonStyle(.borderedProminent).disabled(backup.isRunning);Text(language.text("Your originals stay on this iPhone while Libérons protects them.","Vos originaux restent sur cet iPhone pendant que Libérons les protège.")).font(.caption).foregroundStyle(.secondary)}.padding(16).background(.bar)}}.navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.topBarTrailing){Button(allSelected ? language.text("Deselect all","Tout désélectionner"):language.text("Select all","Tout sélectionner")){if allSelected{selectedIDs.subtract(itemIDs)}else{selectedIDs.formUnion(itemIDs)}}}}}
        .presentationDragIndicator(.visible)
        .sheet(item:$preview){selection in AssetPreviewPager(selection:selection,language:language).presentationDetents([.large]).presentationDragIndicator(.visible).presentationBackground(.black)}
    }

    private var freeSpaceOffer:some View{NavigationStack{VStack(alignment:.leading,spacing:22){Image(systemName:"checkmark.shield.fill").font(.system(size:42)).foregroundStyle(.green);Text(language.text("Protected. Ready to free space.","Protégé. Prêt à libérer de l’espace.")).font(.largeTitle.bold());Text(language.text("These items are safely protected with Libérons. You can now remove the originals from this iPhone.","Ces éléments sont bien protégés avec Libérons. Vous pouvez maintenant retirer les originaux de cet iPhone.")).foregroundStyle(.secondary);VStack(spacing:0){offerRow(language.text("Protected items","Éléments protégés"),"\(cleaner.selectedLocalIdentifiers.count)");Divider();offerRow(language.text("Space you can free","Espace libérable"),freeSize)}.padding(.horizontal,18).background(LiberonsTheme.insetCard,in:RoundedRectangle(cornerRadius:20));Spacer();Button(role:.destructive){Task{await cleaner.deletePreparedFromIPhone();intelligence.refreshDeviceStorage();await intelligence.scan();if cleaner.selectedLocalIdentifiers.isEmpty{showFreeOffer=false}}}label:{Text(language.text("Free \(freeSize) from this iPhone","Libérer \(freeSize) de cet iPhone")).fontWeight(.bold).frame(maxWidth:.infinity).frame(height:48)}.buttonStyle(.borderedProminent).disabled(cleaner.isDeleting);Button(language.text("Keep originals on iPhone","Garder les originaux sur l’iPhone")){showFreeOffer=false}.frame(maxWidth:.infinity)}.padding(24).background(LiberonsTheme.canvas).navigationTitle(language.text("Free space","Libérer de l’espace")).navigationBarTitleDisplayMode(.inline)}.presentationDetents([.large])}
    private func offerRow(_ title:String,_ value:String)->some View{HStack{Text(title);Spacer();Text(value).fontWeight(.semibold)}.padding(.vertical,15)}
    private func toggle(_ id:String){if selectedIDs.contains(id){selectedIDs.remove(id)}else{selectedIDs.insert(id)}}
    private func size(_ bytes:Int64)->String{bytes<=0 ? language.text("0 KB","0 Ko"):ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)}
    private func duration(_ seconds:TimeInterval)->String{let v=max(0,Int(seconds.rounded()));return v>=3600 ? String(format:"%d:%02d:%02d",v/3600,(v%3600)/60,v%60):String(format:"%d:%02d",v/60,v%60)}
    private func itemLabel(_ item:StorageInsightItem)->String{item.duration>0 ? language.text("Video","Vidéo"):language.text("Photo","Photo")}
    private func title(_ kind:StorageInsightItem.Kind)->String{switch kind{case .duplicate:return language.text("Duplicates","Doublons");case .screenshot:return language.text("Screenshots","Captures d’écran");case .video:return language.text("Videos","Vidéos");case .largeVideo:return language.text("Large videos","Vidéos volumineuses");case .longVideo:return language.text("Long videos","Vidéos longues");case .slowMotion:return language.text("Slow motion","Ralenti");case .timeLapse:return "Time-lapse";case .livePhoto:return "Live Photos";case .rawPhoto:return "RAW";case .video4K:return language.text("4K videos","Vidéos 4K");case .other:return language.text("Other large files","Autres fichiers volumineux")}}
    private func icon(_ kind:StorageInsightItem.Kind)->String{switch kind{case .duplicate:return "square.on.square";case .screenshot:return "iphone.gen3";case .video,.largeVideo,.longVideo,.video4K:return "video.fill";case .slowMotion:return "slowmo";case .timeLapse:return "timelapse";case .livePhoto:return "livephoto";case .rawPhoto:return "camera.aperture";case .other:return "doc.fill"}}
}

private struct CategorySelection:Identifiable{let kind:StorageInsightItem.Kind;var id:StorageInsightItem.Kind{kind}}
private struct AssetPreviewSelection:Identifiable{let items:[StorageInsightItem];let startID:String;var id:String{startID}}

private struct AssetPreviewPager:View{
    let selection:AssetPreviewSelection
    @ObservedObject var language:LanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var currentID:String
    init(selection:AssetPreviewSelection,language:LanguageStore){self.selection=selection;self.language=language;_currentID=State(initialValue:selection.startID)}
    var body:some View{ZStack{Color.black.ignoresSafeArea();TabView(selection:$currentID){ForEach(selection.items){item in AssetPreviewPage(item:item).tag(item.id)}}.tabViewStyle(.page(indexDisplayMode:.never));VStack{HStack{Button{dismiss()}label:{Image(systemName:"xmark").font(.headline.bold()).foregroundStyle(.white).frame(width:44,height:44).background(.black.opacity(0.55),in:Circle())};Spacer();if let index=selection.items.firstIndex(where:{$0.id==currentID}){Text("\(index+1) / \(selection.items.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.white).padding(.horizontal,12).padding(.vertical,8).background(.black.opacity(0.55),in:Capsule())}}.padding(.horizontal,18).padding(.top,8);Spacer()}}.statusBarHidden(false)}
}

private struct AssetPreviewPage:View{
    let item:StorageInsightItem
    @State private var image:UIImage?
    @State private var player:AVPlayer?
    @State private var loading=true
    @State private var error=false
    var body:some View{ZStack{Color.black;if let player{NativeVideoPlayer(player:player).ignoresSafeArea().onAppear{player.play()}.onDisappear{player.pause()}}else if let image{Image(uiImage:image).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity)}else if error{VStack(spacing:12){Image(systemName:"icloud.and.arrow.down").font(.largeTitle);Text("Impossible de charger cet élément").font(.headline)}.foregroundStyle(.white.opacity(0.8))}else if loading{ProgressView().tint(.white)}}.task(id:item.id){await load()}}
    private func load() async{loading=true;error=false;player=nil;image=nil;let result=PHAsset.fetchAssets(withLocalIdentifiers:[item.id],options:nil);guard let asset=result.firstObject else{error=true;loading=false;return};if asset.mediaType == .video{let options=PHVideoRequestOptions();options.deliveryMode = .automatic;options.isNetworkAccessAllowed = true;PHImageManager.default().requestPlayerItem(forVideo:asset,options:options){playerItem,_ in DispatchQueue.main.async{if let playerItem{player=AVPlayer(playerItem:playerItem)}else{error=true};loading=false}}}else{let options=PHImageRequestOptions();options.deliveryMode = .highQualityFormat;options.resizeMode = .none;options.isNetworkAccessAllowed = true;PHImageManager.default().requestImage(for:asset,targetSize:PHImageManagerMaximumSize,contentMode:.aspectFit,options:options){value,info in let degraded=(info?[PHImageResultIsDegradedKey] as? Bool) ?? false;DispatchQueue.main.async{if let value{image=value};if !degraded{error=(value==nil);loading=false}}}}}
}

private struct NativeVideoPlayer:UIViewControllerRepresentable{
    let player:AVPlayer
    func makeUIViewController(context:Context)->AVPlayerViewController{let controller=AVPlayerViewController();controller.player=player;controller.showsPlaybackControls=true;controller.videoGravity = .resizeAspect;return controller}
    func updateUIViewController(_ controller:AVPlayerViewController,context:Context){if controller.player !== player{controller.player=player}}
}

private struct AssetThumbnail:View{let localIdentifier:String;let isVideo:Bool;@State private var image:UIImage?;var body:some View{ZStack{RoundedRectangle(cornerRadius:10).fill(Color.secondary.opacity(0.10));if let image{Image(uiImage:image).resizable().scaledToFill()}else{Image(systemName:isVideo ? "play.fill":"photo.fill").foregroundStyle(.secondary)};if isVideo{Image(systemName:"play.fill").font(.caption.bold()).foregroundStyle(.white).padding(6).background(.black.opacity(0.45),in:Circle())}}.frame(width:58,height:58).clipShape(RoundedRectangle(cornerRadius:10)).task(id:localIdentifier){let result=PHAsset.fetchAssets(withLocalIdentifiers:[localIdentifier],options:nil);guard let asset=result.firstObject else{return};let options=PHImageRequestOptions();options.deliveryMode = .opportunistic;options.resizeMode = .fast;options.isNetworkAccessAllowed = false;PHImageManager.default().requestImage(for:asset,targetSize:CGSize(width:160,height:160),contentMode:.aspectFill,options:options){value,_ in if let value{image=value}}}}}
private extension View{func storageAnalysisCard(padding:CGFloat=18)->some View{self.padding(padding).frame(maxWidth:.infinity,alignment:.leading).background(LiberonsTheme.card,in:RoundedRectangle(cornerRadius:24,style:.continuous)).shadow(color:.black.opacity(0.035),radius:14,y:5)}}
