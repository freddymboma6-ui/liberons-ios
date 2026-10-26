import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import Combine

struct AnalyzedLocalFile: Identifiable, Hashable {
    let url: URL
    let name: String
    let sizeBytes: Int64
    let contentType: UTType?
    var id: String { url.standardizedFileURL.path }
}

@MainActor
final class FileStorageAnalysisStore: ObservableObject {
    @Published private(set) var files: [AnalyzedLocalFile] = []
    @Published private(set) var isScanning = false
    @Published private(set) var folderName: String?
    @Published private(set) var errorMessage: String?
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.sizeBytes } }

    func analyze(folder: URL) async {
        isScanning = true; errorMessage = nil; folderName = folder.lastPathComponent
        defer { isScanning = false }
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        do {
            let keys:Set<URLResourceKey>=[.isRegularFileKey,.isHiddenKey,.fileSizeKey,.nameKey,.contentTypeKey]
            guard let enumerator=FileManager.default.enumerator(at:folder,includingPropertiesForKeys:Array(keys),options:[.skipsHiddenFiles,.skipsPackageDescendants]) else { throw CocoaError(.fileReadNoSuchFile) }
            var result:[AnalyzedLocalFile]=[]
            while let value=enumerator.nextObject() as? URL {
                let values=try? value.resourceValues(forKeys:keys)
                guard values?.isRegularFile == true,values?.isHidden != true else{continue}
                let bytes=Int64(values?.fileSize ?? 0);guard bytes>0 else{continue}
                result.append(.init(url:value,name:values?.name ?? value.lastPathComponent,sizeBytes:bytes,contentType:values?.contentType))
            }
            files=result.sorted{$0.sizeBytes>$1.sizeBytes}
        } catch { files=[];errorMessage=error.localizedDescription }
    }

    func delete(_ selected:[AnalyzedLocalFile])->Int {
        var deletedIDs=Set<String>()
        for file in selected { let granted=file.url.startAccessingSecurityScopedResource();defer{if granted{file.url.stopAccessingSecurityScopedResource()}};do{try FileManager.default.removeItem(at:file.url);deletedIDs.insert(file.id)}catch{} }
        files.removeAll{deletedIDs.contains($0.id) || !FileManager.default.fileExists(atPath:$0.url.path)}
        return deletedIDs.count
    }
}

struct FileStorageAnalysisView:View {
    @ObservedObject var language:LanguageStore
    @StateObject private var analysis=FileStorageAnalysisStore()
    @StateObject private var protectedFiles=ProtectedFilesStore()
    @State private var showFolderPicker=false
    @State private var selectedIDs=Set<String>()
    @State private var previewURL:URL?
    @State private var showDeleteConfirmation=false
    @State private var showProtectedRemoval=false
    @State private var protectedSelection:[AnalyzedLocalFile]=[]
    @State private var operationMessage:String?

    private var selectedFiles:[AnalyzedLocalFile]{analysis.files.filter{selectedIDs.contains($0.id)}}
    private var selectedBytes:Int64{selectedFiles.reduce(0){$0+$1.sizeBytes}}

    var body:some View{
        VStack(spacing:0){
            if analysis.files.isEmpty && !analysis.isScanning {
                ScrollView{VStack(spacing:22){
                    ZStack{RoundedRectangle(cornerRadius:24,style:.continuous).fill(Color.blue.opacity(0.10));Image(systemName:"folder.badge.gearshape").font(.system(size:42,weight:.medium)).foregroundStyle(.blue)}.frame(width:88,height:88)
                    Text(language.text("Analyze files","Analyser les fichiers")).font(.title.bold())
                    Text(language.text("Open Files, go to the folder you want to analyze — for example iCloud Drive, Downloads or On My iPhone — then simply tap Open. The folder you are currently viewing is automatically selected and Libérons immediately analyzes its contents.","Dans Fichiers, ouvrez le dossier que vous souhaitez analyser — par exemple iCloud Drive, Téléchargements ou Sur mon iPhone — puis touchez simplement « Ouvrir ». Le dossier affiché à l’écran est automatiquement sélectionné et Libérons analyse immédiatement son contenu.")).font(.body).multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    VStack(alignment:.leading,spacing:10){Label(language.text("All file types","Tous les types de fichiers"),systemImage:"checkmark.circle.fill").foregroundStyle(.blue).fontWeight(.semibold);Text(language.text("Documents, audio, video, images, archives and other file formats can be analyzed and protected with Libérons.","Les documents, fichiers audio, vidéos, images, archives et autres formats peuvent être analysés et protégés avec Libérons.")).font(.subheadline).foregroundStyle(.secondary)}.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:20,style:.continuous))
                    if let error=analysis.errorMessage{Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)}
                    Button{showFolderPicker=true}label:{Label(language.text("Choose a folder","Choisir un dossier"),systemImage:"folder.fill").fontWeight(.semibold).frame(maxWidth:.infinity).frame(height:48)}.buttonStyle(.borderedProminent)
                }.padding(28).frame(maxWidth:620).frame(maxWidth:.infinity)}
            } else if analysis.isScanning {
                VStack(spacing:14){ProgressView();Text(language.text("Analyzing the selected folder…","Analyse du dossier sélectionné…")).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                List{
                    Section{HStack{Label(analysis.folderName ?? language.text("Selected folder","Dossier sélectionné"),systemImage:"folder.fill");Spacer();Button(language.text("Change","Modifier")){showFolderPicker=true}};HStack{Text(language.text("Files analyzed","Fichiers analysés"));Spacer();Text(analysis.files.count.formatted()).fontWeight(.semibold)};HStack{Text(language.text("Total size","Taille totale"));Spacer();Text(size(analysis.totalBytes)).fontWeight(.semibold)}}
                    if let operationMessage{Section{Label(operationMessage,systemImage:"checkmark.circle.fill").foregroundStyle(.green).font(.footnote)}}
                    Section(language.text("Files by size","Fichiers par taille")){ForEach(analysis.files){file in HStack(spacing:12){Button{toggle(file.id)}label:{Image(systemName:selectedIDs.contains(file.id) ? "checkmark.circle.fill":"circle").font(.title3).foregroundStyle(selectedIDs.contains(file.id) ? .blue:.secondary)}.buttonStyle(.plain);Button{previewURL=file.url}label:{HStack(spacing:12){Image(systemName:icon(file)).foregroundStyle(.blue).frame(width:28);VStack(alignment:.leading,spacing:3){Text(file.name).lineLimit(1).foregroundStyle(.primary);Text(size(file.sizeBytes)).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"eye").foregroundStyle(.tertiary)}}.buttonStyle(.plain)}}}
                }.listStyle(.insetGrouped)
            }
        }
        .navigationTitle(language.text("File analysis","Analyse des fichiers")).navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.topBarTrailing){if !analysis.files.isEmpty{let all=selectedIDs.count==analysis.files.count;Button(all ? language.text("Deselect all","Tout désélectionner"):language.text("Select all","Tout sélectionner")){selectedIDs=all ? []:Set(analysis.files.map(\.id))}}}}
        .safeAreaInset(edge:.bottom){if !selectedIDs.isEmpty || protectedFiles.isUploading{VStack(spacing:10){if protectedFiles.isUploading{ProgressView(value:Double(protectedFiles.uploadCompleted),total:Double(max(protectedFiles.uploadTotal,1)));Text(language.text("Protecting \(protectedFiles.uploadCompleted) of \(protectedFiles.uploadTotal) files","Protection de \(protectedFiles.uploadCompleted) sur \(protectedFiles.uploadTotal) fichiers")).font(.caption).foregroundStyle(.secondary)}else{HStack{Text("\(selectedIDs.count) \(language.text("selected","sélectionné(s)"))");Spacer();Text(size(selectedBytes)).fontWeight(.semibold)};Button{let files=selectedFiles;Task{await protectedFiles.protect(files.map(\.url),removeOriginals:false,language:language);let protectedCount=protectedFiles.lastBatchProtected;let failedCount=protectedFiles.lastBatchFailed;if protectedCount>0{operationMessage=language.text("Protection complete: \(protectedCount) file(s) are now stored in Libérons Cloud.","Protection terminée : \(protectedCount) fichier(s) sont maintenant conservés dans Libérons Cloud.");protectedSelection=files.filter{FileManager.default.fileExists(atPath:$0.url.path)};selectedIDs.removeAll();showProtectedRemoval = failedCount == 0 && !protectedSelection.isEmpty}else{operationMessage=protectedFiles.message}}}label:{Label(language.text("Protect with Libérons","Protéger avec Libérons"),systemImage:"checkmark.shield.fill").frame(maxWidth:.infinity).frame(height:44).fontWeight(.semibold)}.buttonStyle(.borderedProminent);Button(role:.destructive){showDeleteConfirmation=true}label:{Label(language.text("Delete without protecting","Supprimer sans protéger"),systemImage:"trash").frame(maxWidth:.infinity).frame(height:44).fontWeight(.semibold)}.buttonStyle(.bordered).tint(.red)}}.padding(16).background(.bar)}}
        .fileImporter(isPresented:$showFolderPicker,allowedContentTypes:[.folder],allowsMultipleSelection:false){result in if case .success(let urls)=result,let folder=urls.first{selectedIDs.removeAll();operationMessage=nil;Task{await analysis.analyze(folder:folder)}}}
        .quickLookPreview($previewURL)
        .confirmationDialog(language.text("Delete selected files?","Supprimer les fichiers sélectionnés ?"),isPresented:$showDeleteConfirmation,titleVisibility:.visible){Button(language.text("Delete permanently","Supprimer définitivement"),role:.destructive){let files=selectedFiles;let deleted=analysis.delete(files);selectedIDs.subtract(files.map(\.id));operationMessage=language.text("\(deleted) file(s) were deleted from the selected folder.","\(deleted) fichier(s) ont été supprimés du dossier sélectionné.")};Button(language.text("Cancel","Annuler"),role:.cancel){}}message:{Text(language.text("These files have not been protected with Libérons. Deleting them may be permanent and cannot be undone.","Ces fichiers n’ont pas été protégés avec Libérons. Leur suppression peut être définitive et irréversible."))}
        .confirmationDialog(language.text("Protection complete","Protection terminée"),isPresented:$showProtectedRemoval,titleVisibility:.visible){Button(language.text("Remove protected originals","Supprimer les originaux protégés"),role:.destructive){let files=protectedSelection;let deleted=analysis.delete(files);protectedSelection=[];operationMessage=language.text("The cloud copies remain protected in Libérons. \(deleted) original file(s) were removed from the selected folder.","Les copies cloud restent protégées dans Libérons. \(deleted) fichier(s) original(aux) ont été supprimés du dossier sélectionné.")};Button(language.text("Keep originals","Conserver les originaux")){protectedSelection=[]}}message:{Text(language.text("Your selected files are now protected in Libérons Cloud. You can remove the originals to free storage or keep them in their current folder.","Les fichiers sélectionnés sont maintenant protégés dans Libérons Cloud. Vous pouvez supprimer les originaux pour libérer de l’espace ou les conserver dans leur dossier actuel."))}
    }

    private func toggle(_ id:String){if selectedIDs.contains(id){selectedIDs.remove(id)}else{selectedIDs.insert(id)}}
    private func size(_ bytes:Int64)->String{ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)}
    private func icon(_ file:AnalyzedLocalFile)->String{if file.contentType?.conforms(to:.pdf)==true{return "doc.richtext.fill"};if file.contentType?.conforms(to:.image)==true{return "photo.fill"};if file.contentType?.conforms(to:.movie)==true{return "video.fill"};if file.contentType?.conforms(to:.audio)==true{return "waveform"};if file.contentType?.conforms(to:.archive)==true{return "doc.zipper"};return "doc.fill"}
}