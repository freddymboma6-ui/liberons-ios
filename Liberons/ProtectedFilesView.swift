import SwiftUI
import Combine
import UniformTypeIdentifiers
import CryptoKit
import Supabase
import QuickLook

struct ProtectedFileItem: Identifiable, Decodable {
    let id: UUID
    let originalFilename: String?
    let mimeType: String
    let sizeBytes: Int64
    let protectedAt: Date?
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id; case originalFilename = "original_filename"; case mimeType = "mime_type"; case sizeBytes = "size_bytes"; case protectedAt = "protected_at"; case createdAt = "created_at" }
}

@MainActor
final class ProtectedFilesStore: ObservableObject {
    @Published private(set) var items:[ProtectedFileItem]=[]
    @Published private(set) var isLoading=false
    @Published private(set) var isUploading=false
    @Published private(set) var uploadTotal=0
    @Published private(set) var uploadCompleted=0
    @Published private(set) var currentFilename:String?
    @Published private(set) var message:String?
    @Published private(set) var lastBatchProtected=0
    @Published private(set) var lastBatchFailed=0

    private struct InitiateResponse:Decodable { struct Upload:Decodable{let url:String;let headers:[String:String]};let asset_id:String;let upload_session_id:String;let upload:Upload }

    func refresh() async {
        isLoading=true; defer{isLoading=false}
        do {
            let response=try await SupabaseService.client.from("media_assets").select("id,original_filename,mime_type,size_bytes,protected_at,created_at").eq("media_type",value:"other").eq("status",value:"protected").order("created_at",ascending:false).limit(5000).execute()
            items=try Self.makeDecoder().decode([ProtectedFileItem].self,from:response.data)
        } catch { message=error.localizedDescription }
    }

    func protect(_ urls:[URL],removeOriginals:Bool,language:LanguageStore) async {
        guard !isUploading,!urls.isEmpty else{return}
        isUploading=true;uploadTotal=urls.count;uploadCompleted=0;lastBatchProtected=0;lastBatchFailed=0;message=nil
        defer{isUploading=false;currentFilename=nil}
        var removalFailures=0
        for source in urls {
            currentFilename=source.lastPathComponent
            do {
                let removed=try await protectOne(source,removeOriginal:removeOriginals)
                lastBatchProtected += 1
                if removeOriginals && !removed{removalFailures += 1}
            } catch { lastBatchFailed += 1 }
            uploadCompleted += 1
        }
        await refresh()
        if lastBatchFailed == 0 {
            if removeOriginals && removalFailures > 0 { message=language.text("Protection complete. Some originals could not be removed by their storage provider.","Protection terminée. Certains originaux n’ont pas pu être supprimés par leur fournisseur de stockage.") }
            else { message=language.text("\(lastBatchProtected) file(s) protected successfully.","\(lastBatchProtected) fichier(s) protégé(s) avec succès.") }
        } else { message=language.text("\(lastBatchProtected) file(s) protected • \(lastBatchFailed) failed.","\(lastBatchProtected) fichier(s) protégé(s) • \(lastBatchFailed) échec(s).") }
        NotificationCenter.default.post(name:.liberonsCloudDidChange,object:nil)
    }

    private func protectOne(_ source:URL,removeOriginal:Bool) async throws->Bool {
        let access=source.startAccessingSecurityScopedResource();defer{if access{source.stopAccessingSecurityScopedResource()}}
        let values=try source.resourceValues(forKeys:[.fileSizeKey,.contentTypeKey,.nameKey])
        guard let fileSize=values.fileSize,fileSize>0 else{throw NSError(domain:"LiberonsFiles",code:1,userInfo:[NSLocalizedDescriptionKey:"The selected file is empty or unavailable."])}
        let filename=values.name ?? source.lastPathComponent
        let mime=values.contentType?.preferredMIMEType ?? UTType(filenameExtension:source.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
        try? FileManager.default.removeItem(at:temp);try FileManager.default.copyItem(at:source,to:temp);defer{try? FileManager.default.removeItem(at:temp)}
        let body:[String:Any]=["filename":filename,"mime_type":mime,"size_bytes":fileSize,"checksum_sha256":try Self.sha256(fileURL:temp),"asset_kind":"file"]
        let data=try await SupabaseService.callFunction("initiate-upload",json:try JSONSerialization.data(withJSONObject:body))
        let initiated=try JSONDecoder().decode(InitiateResponse.self,from:data)
        guard let signedURL=URL(string:initiated.upload.url) else{throw URLError(.badURL)}
        try await SupabaseService.putFile(temp,to:signedURL,headers:initiated.upload.headers)
        let verified=try await SupabaseService.verifyUpload(assetID:initiated.asset_id,uploadSessionID:initiated.upload_session_id)
        let object=try JSONSerialization.jsonObject(with:verified) as? [String:Any]
        guard object?["protected"] as? Bool == true else{throw NSError(domain:"LiberonsFiles",code:2,userInfo:[NSLocalizedDescriptionKey:"Libérons could not verify the protected cloud copy."])}
        guard removeOriginal else{return true};do{try FileManager.default.removeItem(at:source);return true}catch{return false}
    }

    func download(_ item:ProtectedFileItem) async throws->URL {
        let remote=try await SupabaseService.cloudOriginalURL(assetID:item.id);let(temporary,response)=try await URLSession.shared.download(from:remote)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else{throw URLError(.badServerResponse)}
        let directory=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("LiberonsFiles",isDirectory:true);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let target=directory.appendingPathComponent(item.originalFilename ?? item.id.uuidString);try? FileManager.default.removeItem(at:target);try FileManager.default.moveItem(at:temporary,to:target);return target
    }
    func delete(_ item:ProtectedFileItem) async{do{_=try await SupabaseService.deleteCloudMedia(assetID:item.id);items.removeAll{$0.id==item.id};NotificationCenter.default.post(name:.liberonsCloudDidChange,object:nil)}catch{message=error.localizedDescription}}
    nonisolated private static func sha256(fileURL:URL)throws->String{let handle=try FileHandle(forReadingFrom:fileURL);defer{try?handle.close()};var hasher=SHA256();while true{let data=handle.readData(ofLength:1024*1024);if data.isEmpty{break};hasher.update(data:data)};return hasher.finalize().map{String(format:"%02x",$0)}.joined()}
    private static func makeDecoder()->JSONDecoder{let d=JSONDecoder();d.dateDecodingStrategy = .custom{decoder in let c=try decoder.singleValueContainer();let raw=try c.decode(String.self);let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];if let x=f.date(from:raw){return x};let s=ISO8601DateFormatter();s.formatOptions=[.withInternetDateTime];if let x=s.date(from:raw){return x};throw DecodingError.dataCorruptedError(in:c,debugDescription:"Invalid date")};return d}
}

struct ProtectedFilesView:View {
    @ObservedObject var language:LanguageStore
    @StateObject private var store=ProtectedFilesStore()
    @State private var showImporter=false
    @State private var pendingImportURLs:[URL]=[]
    @State private var showProtectionOptions=false
    @State private var exportURL:URL?
    @State private var showExporter=false
    @State private var previewURL:URL?
    @State private var downloadingID:UUID?
    @State private var itemPendingDeletion:ProtectedFileItem?
    private var totalBytes:Int64{store.items.reduce(0){$0+$1.sizeBytes}}

    var body:some View{
        NavigationStack{
            ScrollView{
                VStack(alignment:.leading,spacing:18){
                    HStack(alignment:.top){VStack(alignment:.leading,spacing:5){Text(language.text("Protected files","Fichiers protégés")).font(.system(size:34,weight:.bold,design:.rounded));Text(language.text("Your documents are securely stored in Libérons Cloud.","Vos documents sont conservés en toute sécurité dans Libérons Cloud.")).font(.subheadline).foregroundStyle(.secondary)};Spacer();Button{showImporter=true}label:{Image(systemName:"plus").font(.title2.bold()).frame(width:48,height:48).background(.thinMaterial,in:Circle()).overlay(Circle().stroke(Color.secondary.opacity(0.18)))}.disabled(store.isUploading)}
                    if store.isUploading{uploadCard}
                    else if let message=store.message{statusCard(message)}
                    if !store.items.isEmpty{HStack(spacing:10){metric(language.text("Protected","Protégés"),store.items.count.formatted(),"checkmark.shield.fill");metric(language.text("Cloud storage","Stockage cloud"),ByteCountFormatter.string(fromByteCount:totalBytes,countStyle:.file),"icloud.fill")}}
                    if store.isLoading && store.items.isEmpty{ProgressView().frame(maxWidth:.infinity).padding(.top,80)}
                    else if store.items.isEmpty{emptyCard}
                    else{VStack(spacing:12){ForEach(store.items){fileCard($0)}}}
                }.padding(20).padding(.bottom,40)
            }.background(LiberonsTheme.canvas.ignoresSafeArea()).navigationBarTitleDisplayMode(.inline).toolbar(.hidden,for:.navigationBar)
            .task{await store.refresh()}
            .fileImporter(isPresented:$showImporter,allowedContentTypes:[.item],allowsMultipleSelection:true){result in if case .success(let urls)=result,!urls.isEmpty{pendingImportURLs=urls;showProtectionOptions=true}}
            .sheet(isPresented:$showProtectionOptions){protectionSheet}
            .confirmationDialog(language.text("Delete protected file?","Supprimer le fichier protégé ?"),isPresented:Binding(get:{itemPendingDeletion != nil},set:{if !$0{itemPendingDeletion=nil}}),titleVisibility:.visible){Button(language.text("Delete from Libérons","Supprimer de Libérons"),role:.destructive){guard let item=itemPendingDeletion else{return};itemPendingDeletion=nil;Task{await store.delete(item)}};Button(language.text("Cancel","Annuler"),role:.cancel){itemPendingDeletion=nil}}message:{Text(language.text("This permanently removes the protected cloud copy from Libérons.","Cette action supprime définitivement la copie protégée de Libérons Cloud."))}
            .quickLookPreview($previewURL)
            .fileExporter(isPresented:$showExporter,document:exportURL.map{ExportedLiberonsFile(url:$0)},contentType:exportType,defaultFilename:exportURL?.lastPathComponent ?? "Libérons"){_ in if let exportURL{try?FileManager.default.removeItem(at:exportURL)};self.exportURL=nil}
        }
    }

    private var uploadCard:some View{VStack(alignment:.leading,spacing:12){HStack{ZStack{Circle().fill(Color.blue.opacity(0.12)).frame(width:42,height:42);Image(systemName:"icloud.and.arrow.up.fill").foregroundStyle(.blue)};VStack(alignment:.leading,spacing:3){Text(language.text("Protecting your files","Protection de vos fichiers")).font(.headline);if let name=store.currentFilename{Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)}};Spacer();Text("\(store.uploadCompleted)/\(store.uploadTotal)").font(.headline).monospacedDigit()};ProgressView(value:Double(store.uploadCompleted),total:Double(max(store.uploadTotal,1))).tint(.blue);Text(language.text("Each file is verified before protection is confirmed.","Chaque fichier est vérifié avant la confirmation de sa protection.")).font(.caption).foregroundStyle(.secondary)}.padding(18).background(LiberonsTheme.card,in:RoundedRectangle(cornerRadius:24,style:.continuous))}
    private func statusCard(_ text:String)->some View{HStack(spacing:12){Image(systemName:store.lastBatchFailed==0 ? "checkmark.circle.fill":"exclamationmark.triangle.fill").font(.title2).foregroundStyle(store.lastBatchFailed==0 ? .green:.orange);Text(text).font(.subheadline.weight(.medium));Spacer()}.padding(16).background(LiberonsTheme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))}
    private func metric(_ title:String,_ value:String,_ icon:String)->some View{VStack(alignment:.leading,spacing:10){Image(systemName:icon).foregroundStyle(.blue);Text(value).font(.title3.bold());Text(title).font(.caption).foregroundStyle(.secondary)}.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(LiberonsTheme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))}
    private var emptyCard:some View{VStack(spacing:14){Image(systemName:"doc.badge.arrow.up").font(.system(size:42)).foregroundStyle(.blue);Text(language.text("Protect your first files","Protégez vos premiers fichiers")).font(.title3.bold());Text(language.text("Choose documents or other files to keep a protected copy in Libérons Cloud.","Sélectionnez des documents ou d’autres fichiers afin d’en conserver une copie protégée dans Libérons Cloud.")).multilineTextAlignment(.center).foregroundStyle(.secondary);Button(language.text("Select files","Sélectionner des fichiers")){showImporter=true}.buttonStyle(.borderedProminent)}.padding(28).frame(maxWidth:.infinity).background(LiberonsTheme.card,in:RoundedRectangle(cornerRadius:26,style:.continuous))}
    private func fileCard(_ item:ProtectedFileItem)->some View{HStack(spacing:14){ZStack{RoundedRectangle(cornerRadius:14).fill(Color.blue.opacity(0.10));Image(systemName:icon(for:item)).font(.title2).foregroundStyle(.blue)}.frame(width:52,height:52);VStack(alignment:.leading,spacing:5){Text(item.originalFilename ?? language.text("File","Fichier")).font(.headline).lineLimit(1);HStack(spacing:7){Text(ByteCountFormatter.string(fromByteCount:item.sizeBytes,countStyle:.file));Text("•");Text(language.text("Protected","Protégé"))}.font(.caption).foregroundStyle(.secondary)};Spacer();if downloadingID==item.id{ProgressView()}else{Menu{Button{Task{await preview(item)}}label:{Label(language.text("Open preview","Ouvrir l’aperçu"),systemImage:"eye")};Button{Task{await restore(item)}}label:{Label(language.text("Save to Files","Enregistrer dans Fichiers"),systemImage:"square.and.arrow.down")};Divider();Button(role:.destructive){itemPendingDeletion=item}label:{Label(language.text("Delete from Libérons","Supprimer de Libérons"),systemImage:"trash")}}label:{Image(systemName:"ellipsis").font(.headline).frame(width:40,height:40).background(Color.secondary.opacity(0.08),in:Circle())}}}.padding(16).background(LiberonsTheme.card,in:RoundedRectangle(cornerRadius:22,style:.continuous)).contentShape(Rectangle()).onTapGesture{Task{await preview(item)}}}

    private var protectionSheet:some View{NavigationStack{VStack(alignment:.leading,spacing:22){ZStack{RoundedRectangle(cornerRadius:22).fill(Color.blue.opacity(0.10));Image(systemName:"checkmark.shield.fill").font(.system(size:34)).foregroundStyle(.blue)}.frame(width:72,height:72);VStack(alignment:.leading,spacing:8){Text(language.text("Protect \(pendingImportURLs.count) file(s)","Protéger \(pendingImportURLs.count) fichier(s)")).font(.largeTitle.bold());Text(language.text("Libérons uploads and verifies every selected file before confirming protection.","Libérons transfère et vérifie chaque fichier sélectionné avant de confirmer sa protection.")).foregroundStyle(.secondary)};VStack(spacing:12){Button{startProtection(remove:false)}label:{Label(language.text("Protect and keep originals","Protéger et conserver les originaux"),systemImage:"checkmark.shield.fill").fontWeight(.semibold).frame(maxWidth:.infinity).frame(height:48)}.buttonStyle(.borderedProminent);Button(role:.destructive){startProtection(remove:true)}label:{Label(language.text("Protect, then remove originals","Protéger, puis supprimer les originaux"),systemImage:"trash").fontWeight(.semibold).frame(maxWidth:.infinity).frame(height:48)}.buttonStyle(.bordered).tint(.red)};Text(language.text("Originals are removed only after their protected cloud copies have been verified. Some storage providers may prevent deletion.","Les originaux ne sont supprimés qu’après vérification de leurs copies protégées dans le cloud. Certains fournisseurs de stockage peuvent empêcher leur suppression.")).font(.footnote).foregroundStyle(.secondary);Spacer();Button(language.text("Cancel","Annuler")){pendingImportURLs=[];showProtectionOptions=false}.frame(maxWidth:.infinity)}.padding(24).navigationTitle(language.text("File protection","Protection des fichiers")).navigationBarTitleDisplayMode(.inline)}.presentationDetents([.large]).presentationDragIndicator(.visible)}
    private func startProtection(remove:Bool){let urls=pendingImportURLs;pendingImportURLs=[];showProtectionOptions=false;Task{await store.protect(urls,removeOriginals:remove,language:language)}}
    private var exportType:UTType{exportURL.flatMap{UTType(filenameExtension:$0.pathExtension)} ?? .data}
    private func icon(for item:ProtectedFileItem)->String{let ext=(item.originalFilename ?? "").split(separator:".").last?.lowercased() ?? "";if ext=="pdf"{return "doc.richtext.fill"};if ["zip","rar","7z"].contains(ext){return "doc.zipper"};if ["mp3","wav","m4a","aac"].contains(ext){return "waveform"};if ["jpg","jpeg","png","heic","gif","webp"].contains(ext){return "photo.fill"};if ["mov","mp4","m4v"].contains(ext){return "video.fill"};return "doc.fill"}
    private func preview(_ item:ProtectedFileItem)async{downloadingID=item.id;defer{downloadingID=nil};do{previewURL=try await store.download(item)}catch{}}
    private func restore(_ item:ProtectedFileItem)async{downloadingID=item.id;defer{downloadingID=nil};do{exportURL=try await store.download(item);showExporter=true}catch{}}
}

struct ExportedLiberonsFile:FileDocument{static var readableContentTypes:[UTType]{[.data,.item]};let url:URL;init(url:URL){self.url=url};init(configuration:ReadConfiguration)throws{throw CocoaError(.fileReadUnsupportedScheme)};func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper{try FileWrapper(url:url,options:.immediate)}}