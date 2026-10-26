import SwiftUI
import UniformTypeIdentifiers
import QuickLook

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
        isScanning = true
        errorMessage = nil
        folderName = folder.lastPathComponent
        defer { isScanning = false }
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        do {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey, .fileSizeKey, .nameKey, .contentTypeKey]
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            var result: [AnalyzedLocalFile] = []
            while let value = enumerator.nextObject() as? URL {
                let values = try? value.resourceValues(forKeys: keys)
                guard values?.isRegularFile == true, values?.isHidden != true else { continue }
                let bytes = Int64(values?.fileSize ?? 0)
                result.append(.init(url: value, name: values?.name ?? value.lastPathComponent, sizeBytes: bytes, contentType: values?.contentType))
            }
            files = result.sorted { $0.sizeBytes > $1.sizeBytes }
        } catch {
            files = []
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ selected: [AnalyzedLocalFile]) -> Int {
        var deleted = 0
        for file in selected {
            do { try FileManager.default.removeItem(at: file.url); deleted += 1 }
            catch { }
        }
        let removed = Set(selected.map(\.id))
        files.removeAll { removed.contains($0.id) && !FileManager.default.fileExists(atPath: $0.url.path) }
        return deleted
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
    @State private var showProtectedRemoval = false
    @State private var protectedSelection: [AnalyzedLocalFile] = []
    @State private var operationMessage: String?

    private var selectedFiles: [AnalyzedLocalFile] { analysis.files.filter { selectedIDs.contains($0.id) } }
    private var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        VStack(spacing: 0) {
            if analysis.files.isEmpty && !analysis.isScanning {
                ContentUnavailableView {
                    Label(language.text("Analyze files", "Analyser les fichiers"), systemImage: "folder.badge.gearshape")
                } description: {
                    Text(language.text("Choose a folder to calculate the size of the files it contains. Libérons only analyzes the folder you authorize.", "Choisissez un dossier pour calculer la taille des fichiers qu’il contient. Libérons analyse uniquement le dossier que vous autorisez."))
                } actions: {
                    Button(language.text("Choose a folder", "Choisir un dossier")) { showFolderPicker = true }.buttonStyle(.borderedProminent)
                }
            } else if analysis.isScanning {
                VStack(spacing: 14) { ProgressView(); Text(language.text("Analyzing authorized files…", "Analyse des fichiers autorisés…")).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        HStack { Label(analysis.folderName ?? language.text("Authorized folder", "Dossier autorisé"), systemImage: "folder.fill"); Spacer(); Button(language.text("Change", "Modifier")) { showFolderPicker = true } }
                        HStack { Text(language.text("Files", "Fichiers")); Spacer(); Text(analysis.files.count.formatted()).fontWeight(.semibold) }
                        HStack { Text(language.text("Total size", "Taille totale")); Spacer(); Text(size(analysis.totalBytes)).fontWeight(.semibold) }
                    }
                    if let operationMessage { Section { Text(operationMessage).font(.footnote).foregroundStyle(.secondary) } }
                    Section(language.text("Files by size", "Fichiers par taille")) {
                        ForEach(analysis.files) { file in
                            HStack(spacing: 12) {
                                Button { toggle(file.id) } label: { Image(systemName: selectedIDs.contains(file.id) ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(selectedIDs.contains(file.id) ? .blue : .secondary) }.buttonStyle(.plain)
                                Button { previewURL = file.url } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: icon(file)).foregroundStyle(.blue).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 3) { Text(file.name).lineLimit(1).foregroundStyle(.primary); Text(size(file.sizeBytes)).font(.caption).foregroundStyle(.secondary) }
                                        Spacer(); Image(systemName: "eye").foregroundStyle(.tertiary)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.listStyle(.insetGrouped)
            }
        }
        .navigationTitle(language.text("File analysis", "Analyse des fichiers"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !analysis.files.isEmpty {
                    let all = selectedIDs.count == analysis.files.count
                    Button(all ? language.text("Deselect all", "Tout désélectionner") : language.text("Select all", "Tout sélectionner")) { selectedIDs = all ? [] : Set(analysis.files.map(\.id)) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedIDs.isEmpty {
                VStack(spacing: 10) {
                    HStack { Text("\(selectedIDs.count) \(language.text("selected", "sélectionné(s)"))"); Spacer(); Text(size(selectedBytes)).fontWeight(.semibold) }
                    Button {
                        let files = selectedFiles
                        Task {
                            await protectedFiles.protect(files.map(\.url), removeOriginals: false, language: language)
                            protectedSelection = files
                            showProtectedRemoval = true
                        }
                    } label: { Label(language.text("Protect with Libérons", "Protéger avec Libérons"), systemImage: "checkmark.shield.fill").frame(maxWidth: .infinity).frame(height: 44).fontWeight(.semibold) }.buttonStyle(.borderedProminent).disabled(protectedFiles.isUploading)
                    Button(role: .destructive) { showDeleteConfirmation = true } label: { Label(language.text("Delete without protecting", "Supprimer sans protéger"), systemImage: "trash").frame(maxWidth: .infinity).frame(height: 44).fontWeight(.semibold) }.buttonStyle(.bordered).tint(.red).disabled(protectedFiles.isUploading)
                }.padding(16).background(.bar)
            }
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let folder = urls.first { selectedIDs.removeAll(); Task { await analysis.analyze(folder: folder) } }
        }
        .quickLookPreview($previewURL)
        .confirmationDialog(language.text("Delete selected files?", "Supprimer les fichiers sélectionnés ?"), isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(language.text("Delete permanently", "Supprimer définitivement"), role: .destructive) {
                let files = selectedFiles; let deleted = analysis.delete(files); selectedIDs.subtract(files.map(\.id)); operationMessage = language.text("\(deleted) file(s) deleted from the authorized location.", "\(deleted) fichier(s) supprimé(s) de l’emplacement autorisé.")
            }
            Button(language.text("Cancel", "Annuler"), role: .cancel) { }
        } message: { Text(language.text("These files will be deleted from their current location without being copied to Libérons Cloud.", "Ces fichiers seront supprimés de leur emplacement actuel sans être copiés dans Libérons Cloud.")) }
        .confirmationDialog(language.text("Files protected", "Fichiers protégés"), isPresented: $showProtectedRemoval, titleVisibility: .visible) {
            Button(language.text("Remove protected originals", "Supprimer les originaux protégés"), role: .destructive) {
                let files = protectedSelection; let deleted = analysis.delete(files); selectedIDs.subtract(files.map(\.id)); protectedSelection = []; operationMessage = language.text("Cloud protection is complete. \(deleted) original file(s) were removed from the authorized location.", "La protection cloud est terminée. \(deleted) fichier(s) original(aux) ont été supprimé(s) de l’emplacement autorisé.")
            }
            Button(language.text("Keep originals", "Conserver les originaux")) { selectedIDs.removeAll(); protectedSelection = [] }
        } message: { Text(language.text("The selected files have been copied to Libérons Cloud. You can now remove the originals to free space, or keep them in their current location.", "Les fichiers sélectionnés ont été copiés dans Libérons Cloud. Vous pouvez maintenant supprimer les originaux pour libérer de l’espace ou les conserver dans leur emplacement actuel.")) }
    }

    private func toggle(_ id: String) { if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) } }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func icon(_ file: AnalyzedLocalFile) -> String {
        if file.contentType?.conforms(to: .pdf) == true { return "doc.richtext.fill" }
        if file.contentType?.conforms(to: .image) == true { return "photo.fill" }
        if file.contentType?.conforms(to: .movie) == true { return "video.fill" }
        if file.contentType?.conforms(to: .audio) == true { return "waveform" }
        if file.contentType?.conforms(to: .archive) == true { return "doc.zipper" }
        return "doc.fill"
    }
}
