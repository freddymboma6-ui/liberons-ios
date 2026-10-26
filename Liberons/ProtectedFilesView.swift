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

    enum CodingKeys: String, CodingKey {
        case id
        case originalFilename = "original_filename"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case protectedAt = "protected_at"
        case createdAt = "created_at"
    }
}

@MainActor
final class ProtectedFilesStore: ObservableObject {
    @Published private(set) var items: [ProtectedFileItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUploading = false
    @Published private(set) var uploadTotal = 0
    @Published private(set) var uploadCompleted = 0
    @Published private(set) var message: String?

    private struct InitiateResponse: Decodable {
        struct Upload: Decodable { let url: String; let headers: [String:String] }
        let asset_id: String
        let upload_session_id: String
        let upload: Upload
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await SupabaseService.client.from("media_assets")
                .select("id,original_filename,mime_type,size_bytes,protected_at,created_at")
                .eq("media_type", value: "other").eq("status", value: "protected")
                .order("created_at", ascending: false).execute()
            items = try Self.makeDecoder().decode([ProtectedFileItem].self, from: response.data)
            message = nil
        } catch { message = error.localizedDescription }
    }

    func protect(_ urls: [URL], removeOriginals: Bool, language: LanguageStore) async {
        guard !isUploading, !urls.isEmpty else { return }
        isUploading = true; uploadTotal = urls.count; uploadCompleted = 0; message = nil
        defer { isUploading = false }
        var protectionFailures = 0, removalFailures = 0
        for source in urls {
            do {
                let removed = try await protectOne(source, removeOriginal: removeOriginals)
                uploadCompleted += 1
                if removeOriginals && !removed { removalFailures += 1 }
            } catch { protectionFailures += 1; message = error.localizedDescription }
        }
        await refresh()
        if protectionFailures == 0 && removalFailures == 0 {
            message = removeOriginals ? language.text("Files protected successfully. Originals removed where permitted.", "Fichiers protégés avec succès. Les originaux ont été supprimés lorsque cela était autorisé.") : language.text("Files protected successfully.", "Fichiers protégés avec succès.")
        } else if protectionFailures == 0 {
            message = language.text("All files are protected. Some originals could not be removed by their storage provider.", "Tous les fichiers sont protégés. Certains originaux n’ont pas pu être supprimés par leur fournisseur de stockage.")
        } else {
            message = language.text("\(uploadCompleted) file(s) protected. \(protectionFailures) file(s) could not be protected.", "\(uploadCompleted) fichier(s) protégé(s). \(protectionFailures) fichier(s) n’ont pas pu être protégés.")
        }
        NotificationCenter.default.post(name: .liberonsCloudDidChange, object: nil)
    }

    private func protectOne(_ source: URL, removeOriginal: Bool) async throws -> Bool {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .nameKey])
        guard let fileSize = values.fileSize, fileSize > 0 else { throw NSError(domain:"LiberonsFiles",code:1,userInfo:[NSLocalizedDescriptionKey:"The selected file is empty or unavailable."]) }
        let filename = values.name ?? source.lastPathComponent
        let mime = values.contentType?.preferredMIMEType ?? UTType(filenameExtension: source.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
        try? FileManager.default.removeItem(at: temp); try FileManager.default.copyItem(at: source, to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let body:[String:Any] = ["filename":filename,"mime_type":mime,"size_bytes":fileSize,"checksum_sha256":try Self.sha256(fileURL:temp),"asset_kind":"file"]
        let data = try await SupabaseService.callFunction("initiate-upload", json: try JSONSerialization.data(withJSONObject: body))
        let initiated = try JSONDecoder().decode(InitiateResponse.self, from:data)
        guard let signedURL = URL(string:initiated.upload.url) else { throw URLError(.badURL) }
        try await SupabaseService.putFile(temp, to:signedURL, headers:initiated.upload.headers)
        let verified = try await SupabaseService.verifyUpload(assetID:initiated.asset_id, uploadSessionID:initiated.upload_session_id)
        let object = try JSONSerialization.jsonObject(with:verified) as? [String:Any]
        guard object?["protected"] as? Bool == true else { throw NSError(domain:"LiberonsFiles",code:2,userInfo:[NSLocalizedDescriptionKey:"Libérons could not verify the protected cloud copy."]) }
        guard removeOriginal else { return true }
        do { try FileManager.default.removeItem(at:source); return true } catch { return false }
    }

    func download(_ item: ProtectedFileItem) async throws -> URL {
        let remote = try await SupabaseService.cloudOriginalURL(assetID:item.id)
        let (temporary,response) = try await URLSession.shared.download(from:remote)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let directory=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("LiberonsFiles",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let target=directory.appendingPathComponent(item.originalFilename ?? item.id.uuidString)
        try? FileManager.default.removeItem(at:target); try FileManager.default.moveItem(at:temporary,to:target)
        return target
    }

    func delete(_ item: ProtectedFileItem) async {
        do { _ = try await SupabaseService.deleteCloudMedia(assetID:item.id); items.removeAll{$0.id==item.id}; NotificationCenter.default.post(name:.liberonsCloudDidChange,object:nil) }
        catch { message=error.localizedDescription }
    }

    nonisolated private static func sha256(fileURL:URL)throws->String { let handle=try FileHandle(forReadingFrom:fileURL); defer{try? handle.close()}; var hasher=SHA256(); while true{let data=handle.readData(ofLength:1024*1024);if data.isEmpty{break};hasher.update(data:data)};return hasher.finalize().map{String(format:"%02x",$0)}.joined() }
    private static func makeDecoder()->JSONDecoder { let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .custom{decoder in let c=try decoder.singleValueContainer();let raw=try c.decode(String.self);let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];if let d=f.date(from:raw){return d};let s=ISO8601DateFormatter();s.formatOptions=[.withInternetDateTime];if let d=s.date(from:raw){return d};throw DecodingError.dataCorruptedError(in:c,debugDescription:"Invalid ISO-8601 timestamp: \(raw)")};return decoder }
}

struct ProtectedFilesView: View {
    @ObservedObject var language: LanguageStore
    @StateObject private var store=ProtectedFilesStore()
    @State private var showImporter=false
    @State private var pendingImportURLs:[URL]=[]
    @State private var showProtectionOptions=false
    @State private var exportURL:URL?
    @State private var showExporter=false
    @State private var previewURL:URL?
    @State private var downloadingID:UUID?
    @State private var itemPendingDeletion:ProtectedFileItem?

    var body:some View {
        NavigationStack {
            Group {
                if store.isLoading && store.items.isEmpty { ProgressView(language.text("Loading protected files…","Chargement des fichiers protégés…")) }
                else if store.items.isEmpty {
                    ContentUnavailableView { Label(language.text("Protect files","Protéger des fichiers"),systemImage:"doc.badge.arrow.up") } description: { Text(language.text("Secure documents and other files in Libérons Cloud using your existing storage plan.","Sécurisez vos documents et autres fichiers dans Libérons Cloud avec votre espace de stockage actuel.")) } actions: { Button(language.text("Select files","Sélectionner des fichiers")){showImporter=true}.buttonStyle(.borderedProminent) }
                } else {
                    List {
                        if store.isUploading { Section { VStack(alignment:.leading,spacing:8){ProgressView(value:Double(store.uploadCompleted),total:Double(max(store.uploadTotal,1)));Text(language.text("Protecting files: \(store.uploadCompleted) of \(store.uploadTotal)","Protection des fichiers : \(store.uploadCompleted) sur \(store.uploadTotal)")).font(.caption).foregroundStyle(.secondary)}.padding(.vertical,4) } }
                        if let message=store.message { Section{Text(message).font(.footnote).foregroundStyle(.secondary)} }
                        Section(language.text("Protected files","Fichiers protégés")) {
                            ForEach(store.items){item in
                                Button { Task{await preview(item)} } label: {
                                    HStack(spacing:12){Image(systemName:icon(for:item)).font(.title2).foregroundStyle(.blue).frame(width:34);VStack(alignment:.leading,spacing:3){Text(item.originalFilename ?? language.text("File","Fichier")).lineLimit(1).foregroundStyle(.primary);Text(ByteCountFormatter.string(fromByteCount:item.sizeBytes,countStyle:.file)).font(.caption).foregroundStyle(.secondary)};Spacer();if downloadingID==item.id{ProgressView()}else{Image(systemName:"eye").foregroundStyle(.secondary)}}.padding(.vertical,4)
                                }.buttonStyle(.plain).disabled(downloadingID != nil)
                                .swipeActions(edge:.trailing,allowsFullSwipe:false){Button(role:.destructive){itemPendingDeletion=item}label:{Label(language.text("Delete","Supprimer"),systemImage:"trash")}}
                                .contextMenu {
                                    Button{Task{await preview(item)}}label:{Label(language.text("Preview","Aperçu"),systemImage:"eye")}
                                    Button{Task{await restore(item)}}label:{Label(language.text("Save to Files","Enregistrer dans Fichiers"),systemImage:"square.and.arrow.down")}
                                    Button(role:.destructive){itemPendingDeletion=item}label:{Label(language.text("Delete from Libérons","Supprimer de Libérons"),systemImage:"trash")}
                                }
                            }
                        }
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle(language.text("Files","Fichiers"))
            .toolbar{ToolbarItem(placement:.topBarTrailing){Button{showImporter=true}label:{Image(systemName:"plus")}.disabled(store.isUploading)}}
            .task{await store.refresh()}
            .fileImporter(isPresented:$showImporter,allowedContentTypes:[.item],allowsMultipleSelection:true){result in if case .success(let urls)=result,!urls.isEmpty{pendingImportURLs=urls;showProtectionOptions=true}}
            .confirmationDialog(language.text("Protect selected files","Protéger les fichiers sélectionnés"),isPresented:$showProtectionOptions,titleVisibility:.visible){
                Button(language.text("Protect and keep originals","Protéger et conserver les originaux")){let urls=pendingImportURLs;pendingImportURLs=[];Task{await store.protect(urls,removeOriginals:false,language:language)}}
                Button(language.text("Protect and remove originals","Protéger et supprimer les originaux"),role:.destructive){let urls=pendingImportURLs;pendingImportURLs=[];Task{await store.protect(urls,removeOriginals:true,language:language)}}
                Button(language.text("Cancel","Annuler"),role:.cancel){pendingImportURLs=[]}
            } message:{Text(language.text("Libérons verifies each cloud copy before attempting to remove its original. Some Files providers may not permit deletion.","Libérons vérifie chaque copie cloud avant de tenter de supprimer son original. Certains fournisseurs de fichiers peuvent ne pas autoriser la suppression."))}
            .confirmationDialog(language.text("Delete protected file?","Supprimer le fichier protégé ?"),isPresented:Binding(get:{itemPendingDeletion != nil},set:{if !$0{itemPendingDeletion=nil}}),titleVisibility:.visible){
                Button(language.text("Delete from Libérons","Supprimer de Libérons"),role:.destructive){guard let item=itemPendingDeletion else{return};itemPendingDeletion=nil;Task{await store.delete(item)}}
                Button(language.text("Cancel","Annuler"),role:.cancel){itemPendingDeletion=nil}
            } message:{Text(language.text("This permanently removes the protected cloud copy from Libérons. This action cannot be undone.","Cette action supprime définitivement la copie protégée de Libérons Cloud. Cette action est irréversible."))}
            .quickLookPreview($previewURL)
            .fileExporter(isPresented:$showExporter,document:exportURL.map{ExportedLiberonsFile(url:$0)},contentType:exportType,defaultFilename:exportURL?.lastPathComponent ?? "Libérons"){_ in if let exportURL{try? FileManager.default.removeItem(at:exportURL)};self.exportURL=nil}
        }
    }

    private var exportType:UTType{exportURL.flatMap{UTType(filenameExtension:$0.pathExtension)} ?? .data}
    private func icon(for item:ProtectedFileItem)->String{let ext=(item.originalFilename ?? "").split(separator:".").last?.lowercased() ?? "";if ext=="pdf"{return "doc.richtext.fill"};if ["zip","rar","7z"].contains(ext){return "doc.zipper"};if ["mp3","wav","m4a","aac"].contains(ext){return "waveform"};if ["jpg","jpeg","png","heic","gif","webp"].contains(ext){return "photo.fill"};if ["mov","mp4","m4v"].contains(ext){return "video.fill"};return "doc.fill"}
    private func preview(_ item:ProtectedFileItem)async{downloadingID=item.id;defer{downloadingID=nil};do{previewURL=try await store.download(item)}catch{}}
    private func restore(_ item:ProtectedFileItem)async{downloadingID=item.id;defer{downloadingID=nil};do{exportURL=try await store.download(item);showExporter=true}catch{}}
}

struct ExportedLiberonsFile:FileDocument{static var readableContentTypes:[UTType]{[.data,.item]};let url:URL;init(url:URL){self.url=url};init(configuration:ReadConfiguration)throws{throw CocoaError(.fileReadUnsupportedScheme)};func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper{try FileWrapper(url:url,options:.immediate)}}
