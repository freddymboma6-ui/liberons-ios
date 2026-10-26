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
    private var authorizedFolderURL: URL?

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.sizeBytes } }

    func analyze(folder: URL) async {
        isScanning = true
        errorMessage = nil
        folderName = folder.lastPathComponent
        authorizedFolderURL = folder
        defer { isScanning = false }
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        do {
            let keys: Set<URLResourceKey> = [.isRegularFileKey,.isHiddenKey,.fileSizeKey,.nameKey,.contentTypeKey]
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles,.skipsPackageDescendants]) else { throw CocoaError(.fileReadNoSuchFile) }
            var result: [AnalyzedLocalFile] = []
            while let value = enumerator.nextObject() as? URL {
                let values = try? value.resourceValues(forKeys: keys)
                guard values?.isRegularFile == true, values?.isHidden != true else { continue }
                let bytes = Int64(values?.fileSize ?? 0); guard bytes > 0 else { continue }
                result.append(.init(url: value, name: values?.name ?? value.lastPathComponent, sizeBytes: bytes, contentType: values?.contentType))
            }
            files = result.sorted { $0.sizeBytes > $1.sizeBytes }
        } catch { files = []; errorMessage = error.localizedDescription }
    }

    func beginAuthorizedFolderAccess() -> Bool { guard let folder = authorizedFolderURL else { return false }; return folder.startAccessingSecurityScopedResource() }
    func endAuthorizedFolderAccess(_ started: Bool) { guard started, let folder = authorizedFolderURL else { return }; folder.stopAccessingSecurityScopedResource() }

    func delete(_ selected: [AnalyzedLocalFile]) -> Int {
        let folderAccess = beginAuthorizedFolderAccess(); defer { endAuthorizedFolderAccess(folderAccess) }
        var deletedIDs = Set<String>()
        for file in selected { do { try FileManager.default.removeItem(at: file.url); deletedIDs.insert(file.id) } catch {} }
        files.removeAll { deletedIDs.contains($0.id) || !FileManager.default.fileExists(atPath: $0.url.path) }
        return deletedIDs.count
    }
}

struct FileStorageAnalysisView: View {
    @ObservedObject var language: LanguageStore
    @StateObject private var analysis = FileStorageAnalysisStore()
    @StateObject private var protectedFiles = ProtectedFilesStore()
    @State private var showFolderPicker = false
    @State private var selectedIDs = Set<String>()
    @State private var previewURL: URL?
    @State private var showDeleteConfirmation = false
    @State private var showProtectionSuccess = false
    @State private var protectedSelection: [AnalyzedLocalFile] = []
    @State private var protectedSelectionBytes: Int64 = 0
    @State private var operationMessage: String?
    @State private var operationIsError = false
    @State private var showOperationAlert = false

    private var selectedFiles: [AnalyzedLocalFile] { analysis.files.filter { selectedIDs.contains($0.id) } }
    private var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        VStack(spacing: 0) {
            if analysis.files.isEmpty && !analysis.isScanning {
                ScrollView { VStack(spacing:22) {
                    ZStack { RoundedRectangle(cornerRadius:24,style:.continuous).fill(Color.blue.opacity(0.10)); Image(systemName:"folder.badge.gearshape").font(.system(size:42,weight:.medium)).foregroundStyle(.blue) }.frame(width:88,height:88)
                    Text(language.text("Analyze files","Analyser les fichiers")).font(.title.bold())
                    Text(language.text("Open Files, go to the folder you want to analyze — for example iCloud Drive, Downloads or On My iPhone — then simply tap Open. The folder currently displayed is automatically selected and Libérons immediately analyzes its contents.","Dans Fichiers, ouvrez le dossier que vous souhaitez analyser — par exemple iCloud Drive, Téléchargements ou Sur mon iPhone — puis touchez simplement « Ouvrir ». Le dossier actuellement affiché est automatiquement sélectionné et Libérons analyse immédiatement son contenu.")).font(.body).multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    VStack(alignment:.leading,spacing:10) { Label(language.text("All file types","Tous les types de fichiers"),systemImage:"checkmark.circle.fill").foregroundStyle(.blue).fontWeight(.semibold); Text(language.text("Documents, audio, video, images, archives and other file formats can be analyzed and protected with Libérons.","Les documents, fichiers audio, vidéos, images, archives et autres formats peuvent être analysés et protégés avec Libérons.")).font(.subheadline).foregroundStyle(.secondary) }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:20,style:.continuous))
                    if let error=analysis.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                    Button { showFolderPicker=true } label: { Label(language.text("Choose a folder","Choisir un dossier"),systemImage:"folder.fill").fontWeight(.semibold).frame(maxWidth:.infinity).frame(height:48) }.buttonStyle(.borderedProminent)
                }.padding(28).frame(maxWidth:620).frame(maxWidth:.infinity) }
            } else if analysis.isScanning {
                VStack(spacing:14) { ProgressView(); Text(language.text("Analyzing the selected folder…","Analyse du dossier sélectionné…")).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                List {
                    Section { HStack { Label(analysis.folderName ?? language.text("Selected folder","Dossier sélectionné"),systemImage:"folder.fill"); Spacer(); Button(language.text("Change","Modifier")){showFolderPicker=true} }; HStack { Text(language.text("Files analyzed","Fichiers analysés")); Spacer(); Text(analysis.files.count.formatted()).fontWeight(.semibold) }; HStack { Text(language.text("Total size","Taille totale")); Spacer(); Text(size(analysis.totalBytes)).fontWeight(.semibold) } }
                    if let operationMessage, !operationIsError { Section { Label(operationMessage,systemImage:"checkmark.circle.fill").foregroundStyle(.green).font(.footnote) } }
                    Section(language.text("Files by size","Fichiers par taille")) { ForEach(analysis.files) { file in HStack(spacing:12) { Button { toggle(file.id) } label: { Image(systemName:selectedIDs.contains(file.id) ? "checkmark.circle.fill":"circle").font(.title3).foregroundStyle(selectedIDs.contains(file.id) ? .blue:.secondary) }.buttonStyle(.plain); Button { previewURL=file.url } label: { HStack(spacing:12) { Image(systemName:icon(file)).foregroundStyle(.blue).frame(width:28); VStack(alignment:.leading,spacing:3) { Text(file.name).lineLimit(1).foregroundStyle(.primary); Text(size(file.sizeBytes)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"eye").foregroundStyle(.tertiary) } }.buttonStyle(.plain) } } }
                }.listStyle(.insetGrouped)
            }
        }
        .navigationTitle(language.text("File analysis","Analyse des fichiers")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.topBarTrailing) { if !analysis.files.isEmpty { let all=selectedIDs.count==analysis.files.count; Button(all ? language.text("Deselect all","Tout désélectionner") : language.text("Select all","Tout sélectionner")) { selectedIDs=all ? []:Set(analysis.files.map(\.id)) } } } }
        .safeAreaInset(edge:.bottom) { if !selectedIDs.isEmpty || protectedFiles.isUploading { VStack(spacing:10) { if protectedFiles.isUploading { ProgressView(value:Double(protectedFiles.uploadCompleted),total:Double(max(protectedFiles.uploadTotal,1))).tint(.blue); HStack { Label(language.text("Securing in Libérons Cloud","Sécurisation dans Libérons Cloud"),systemImage:"icloud.and.arrow.up.fill"); Spacer(); Text("\(protectedFiles.uploadCompleted)/\(protectedFiles.uploadTotal)").monospacedDigit() }.font(.caption).foregroundStyle(.secondary) } else { HStack { Text(selectionLabel(selectedIDs.count)); Spacer(); Text(size(selectedBytes)).fontWeight(.semibold) }; Button { protectSelection() } label: { Label(language.text("Protect with Libérons","Protéger avec Libérons"),systemImage:"checkmark.shield.fill").frame(maxWidth:.infinity).frame(height:44).fontWeight(.semibold) }.buttonStyle(.borderedProminent); Button(role:.destructive) { showDeleteConfirmation=true } label: { Label(language.text("Delete without protecting","Supprimer sans protéger"),systemImage:"trash").frame(maxWidth:.infinity).frame(height:44).fontWeight(.semibold) }.buttonStyle(.bordered).tint(.red) } }.padding(16).background(.bar) } }
        .fileImporter(isPresented:$showFolderPicker,allowedContentTypes:[.folder],allowsMultipleSelection:false) { result in if case .success(let urls)=result,let folder=urls.first { selectedIDs.removeAll();operationMessage=nil;operationIsError=false;Task{await analysis.analyze(folder:folder)} } }
        .quickLookPreview($previewURL)
        .sheet(isPresented:$showProtectionSuccess) { protectionSuccessSheet }
        .alert(language.text("Protection failed","Échec de la protection"),isPresented:$showOperationAlert) { Button("OK",role:.cancel){} } message: { Text(operationMessage ?? "") }
        .confirmationDialog(language.text("Delete selected files?","Supprimer les fichiers sélectionnés ?"),isPresented:$showDeleteConfirmation,titleVisibility:.visible) { Button(language.text("Delete permanently","Supprimer définitivement"),role:.destructive) { let files=selectedFiles;let deleted=analysis.delete(files);selectedIDs.subtract(files.map(\.id));operationIsError=deleted != files.count;operationMessage=language.text("\(deleted) file(s) were deleted from the selected folder.","\(deleted) fichier(s) ont été supprimés du dossier sélectionné.") }; Button(language.text("Cancel","Annuler"),role:.cancel){} } message: { Text(language.text("These files have not been protected with Libérons. Deleting them may be permanent and cannot be undone.","Ces fichiers n’ont pas été protégés avec Libérons. Leur suppression peut être définitive et irréversible.")) }
    }

    private var protectionSuccessSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width:38,height:5).padding(.top,10)
            VStack(spacing:20) {
                ZStack { Circle().fill(Color.green.opacity(0.12)).frame(width:82,height:82); Image(systemName:"checkmark.shield.fill").font(.system(size:38,weight:.semibold)).foregroundStyle(.green) }
                VStack(spacing:8) {
                    Text(language.text("Protected in Libérons","Protégé dans Libérons")).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(successDescription).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                }
                HStack(spacing:12) {
                    successMetric(icon:"checkmark.shield.fill",value:protectedSelection.count.formatted(),label:language.text(protectedSelection.count == 1 ? "File" : "Files",protectedSelection.count == 1 ? "Fichier" : "Fichiers"))
                    successMetric(icon:"icloud.fill",value:size(protectedSelectionBytes),label:language.text("Protected","Protégé"))
                }
                VStack(spacing:12) {
                    Button { keepProtectedOriginals() } label: { Label(language.text("Keep originals","Conserver les originaux"),systemImage:"checkmark").fontWeight(.semibold).frame(maxWidth:.infinity).frame(height:50) }.buttonStyle(.borderedProminent)
                    Button(role:.destructive) { removeProtectedOriginals() } label: { Label(language.text("Remove originals from this device","Supprimer les originaux de cet appareil"),systemImage:"trash").fontWeight(.semibold).frame(maxWidth:.infinity).frame(height:50) }.buttonStyle(.bordered).tint(.red)
                }
                HStack(alignment:.top,spacing:8) { Image(systemName:"lock.shield.fill").foregroundStyle(.blue); Text(language.text("Your protected copies remain available in Libérons Cloud even if you remove the originals.","Vos copies protégées restent disponibles dans Libérons Cloud même si vous supprimez les originaux.")).font(.footnote).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).padding(14).background(Color.blue.opacity(0.07),in:RoundedRectangle(cornerRadius:16,style:.continuous))
            }.padding(24)
        }
        .presentationDetents([.medium,.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
        .interactiveDismissDisabled(false)
    }

    private func successMetric(icon:String,value:String,label:String)->some View { VStack(alignment:.leading,spacing:8) { Image(systemName:icon).foregroundStyle(.blue); Text(value).font(.title3.bold()).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.secondary.opacity(0.07),in:RoundedRectangle(cornerRadius:18,style:.continuous)) }

    private var successDescription: String {
        let count=protectedSelection.count
        if language.language == .french { return count == 1 ? "Votre fichier est maintenant conservé en toute sécurité dans Libérons Cloud." : "Vos \(count) fichiers sont maintenant conservés en toute sécurité dans Libérons Cloud." }
        return count == 1 ? "Your file is now securely stored in Libérons Cloud." : "Your \(count) files are now securely stored in Libérons Cloud."
    }

    private func keepProtectedOriginals() { showProtectionSuccess=false;protectedSelection=[];protectedSelectionBytes=0;operationIsError=false;operationMessage=language.text("Protection complete. Your protected files are available in Libérons Cloud.","Protection terminée. Vos fichiers protégés sont disponibles dans Libérons Cloud.") }

    private func removeProtectedOriginals() {
        let files=protectedSelection
        let deleted=analysis.delete(files)
        showProtectionSuccess=false;protectedSelection=[];protectedSelectionBytes=0
        operationIsError=deleted != files.count
        operationMessage=language.text("Protected copies remain in Libérons Cloud. \(deleted) original file(s) were removed.","Les copies protégées restent dans Libérons Cloud. \(deleted) fichier(s) original(aux) ont été supprimé(s).")
        if operationIsError { showOperationAlert=true }
    }

    private func protectSelection() {
        let files=selectedFiles;guard !files.isEmpty else{return}
        Task {
            let folderAccess=analysis.beginAuthorizedFolderAccess();defer{analysis.endAuthorizedFolderAccess(folderAccess)}
            await protectedFiles.protect(files.map(\.url),removeOriginals:false,language:language)
            let protectedCount=protectedFiles.lastBatchProtected;let failedCount=protectedFiles.lastBatchFailed
            if protectedCount == files.count && failedCount == 0 {
                operationIsError=false;operationMessage=nil
                protectedSelection=files.filter{FileManager.default.fileExists(atPath:$0.url.path)}
                protectedSelectionBytes=files.reduce(0){$0+$1.sizeBytes}
                selectedIDs.removeAll()
                showProtectionSuccess=true
            } else {
                operationIsError=true
                operationMessage=protectedFiles.message ?? language.text("The selected file could not be protected. Its original has not been removed.","Le fichier sélectionné n’a pas pu être protégé. Son original n’a pas été supprimé.")
                showOperationAlert=true
            }
        }
    }

    private func selectionLabel(_ count:Int)->String { if language.language == .french { return count == 1 ? "1 sélectionné" : "\(count) sélectionnés" }; return count == 1 ? "1 selected" : "\(count) selected" }
    private func toggle(_ id:String){if selectedIDs.contains(id){selectedIDs.remove(id)}else{selectedIDs.insert(id)}}
    private func size(_ bytes:Int64)->String{ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)}
    private func icon(_ file:AnalyzedLocalFile)->String{if file.contentType?.conforms(to:.pdf)==true{return "doc.richtext.fill"};if file.contentType?.conforms(to:.image)==true{return "photo.fill"};if file.contentType?.conforms(to:.movie)==true{return "video.fill"};if file.contentType?.conforms(to:.audio)==true{return "waveform"};if file.contentType?.conforms(to:.archive)==true{return "doc.zipper"};return "doc.fill"}
}
