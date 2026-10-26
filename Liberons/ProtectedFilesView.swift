import SwiftUI
import Combine
import UniformTypeIdentifiers
import CryptoKit
import Supabase

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
            let response = try await SupabaseService.client
                .from("media_assets")
                .select("id,original_filename,mime_type,size_bytes,protected_at,created_at")
                .eq("media_type", value: "other")
                .eq("status", value: "protected")
                .order("created_at", ascending: false)
                .execute()
            items = try Self.makeDecoder().decode([ProtectedFileItem].self, from: response.data)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func protect(_ urls: [URL], language: LanguageStore) async {
        guard !isUploading, !urls.isEmpty else { return }
        isUploading = true
        uploadTotal = urls.count
        uploadCompleted = 0
        message = nil
        defer { isUploading = false }

        var failures = 0
        var processed = 0
        for source in urls {
            do {
                try await protectOne(source)
                uploadCompleted += 1
            } catch {
                failures += 1
                message = error.localizedDescription
            }
            processed += 1
            if processed == uploadTotal { /* keeps progress state coherent for mixed success/failure batches */ }
        }
        await refresh()
        if failures == 0 {
            message = language.text("Files protected ✓", "Fichiers protégés ✓")
        } else {
            message = language.text("\(uploadCompleted) protected • \(failures) failed", "\(uploadCompleted) protégés • \(failures) échecs")
        }
        NotificationCenter.default.post(name: .liberonsCloudDidChange, object: nil)
    }

    private func protectOne(_ source: URL) async throws {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .nameKey])
        guard let fileSize = values.fileSize, fileSize > 0 else {
            throw NSError(domain: "LiberonsFiles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty file"])
        }
        let filename = values.name ?? source.lastPathComponent
        let mime = values.contentType?.preferredMIMEType ?? UTType(filenameExtension: source.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
        try? FileManager.default.removeItem(at: temp)
        try FileManager.default.copyItem(at: source, to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let checksum = try Self.sha256(fileURL: temp)
        let body: [String:Any] = [
            "filename": filename,
            "mime_type": mime,
            "size_bytes": fileSize,
            "checksum_sha256": checksum,
            "asset_kind": "file"
        ]
        let data = try await SupabaseService.callFunction("initiate-upload", json: try JSONSerialization.data(withJSONObject: body))
        let initiated = try JSONDecoder().decode(InitiateResponse.self, from: data)
        guard let signedURL = URL(string: initiated.upload.url) else { throw URLError(.badURL) }
        try await SupabaseService.putFile(temp, to: signedURL, headers: initiated.upload.headers)
        let verified = try await SupabaseService.verifyUpload(assetID: initiated.asset_id, uploadSessionID: initiated.upload_session_id)
        let object = try JSONSerialization.jsonObject(with: verified) as? [String:Any]
        guard object?["protected"] as? Bool == true else {
            throw NSError(domain: "LiberonsFiles", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cloud verification failed"])
        }
    }

    func download(_ item: ProtectedFileItem) async throws -> URL {
        let remote = try await SupabaseService.cloudOriginalURL(assetID: item.id)
        let (temporary, response) = try await URLSession.shared.download(from: remote)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LiberonsFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(item.originalFilename ?? item.id.uuidString)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        return target
    }

    func delete(_ item: ProtectedFileItem) async {
        do {
            _ = try await SupabaseService.deleteCloudMedia(assetID: item.id)
            items.removeAll { $0.id == item.id }
            NotificationCenter.default.post(name: .liberonsCloudDidChange, object: nil)
        } catch { message = error.localizedDescription }
    }

    nonisolated private static func sha256(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 1024 * 1024)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 timestamp: \(raw)")
        }
        return decoder
    }
}

struct ProtectedFilesView: View {
    @ObservedObject var language: LanguageStore
    @StateObject private var store = ProtectedFilesStore()
    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var downloadingID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.items.isEmpty {
                    ProgressView(language.text("Loading files…", "Chargement des fichiers…"))
                } else if store.items.isEmpty {
                    ContentUnavailableView {
                        Label(language.text("Protect your files", "Protégez vos fichiers"), systemImage: "doc.badge.arrow.up")
                    } description: {
                        Text(language.text("Keep documents and other files safely in your Libérons storage.", "Conservez vos documents et autres fichiers en sécurité dans votre espace Libérons."))
                    } actions: {
                        Button(language.text("Choose files", "Choisir des fichiers")) { showImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if store.isUploading {
                            Section {
                                VStack(alignment: .leading, spacing: 8) {
                                    ProgressView(value: Double(store.uploadCompleted), total: Double(max(store.uploadTotal, 1)))
                                    Text(language.text("Protecting \(store.uploadCompleted) of \(store.uploadTotal)…", "Protection de \(store.uploadCompleted) sur \(store.uploadTotal)…"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }
                        }
                        if let message = store.message {
                            Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                        }
                        Section(language.text("Protected files", "Fichiers protégés")) {
                            ForEach(store.items) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: icon(for: item)).font(.title2).foregroundStyle(.blue).frame(width: 34)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.originalFilename ?? language.text("File", "Fichier")).lineLimit(1)
                                        Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Menu {
                                        Button { Task { await restore(item) } } label: { Label(language.text("Save to Files", "Enregistrer dans Fichiers"), systemImage: "square.and.arrow.down") }
                                        Button(role: .destructive) { Task { await store.delete(item) } } label: { Label(language.text("Delete from Libérons", "Supprimer de Libérons"), systemImage: "trash") }
                                    } label: {
                                        if downloadingID == item.id { ProgressView() } else { Image(systemName: "ellipsis.circle").font(.title3) }
                                    }.disabled(downloadingID != nil)
                                }.padding(.vertical, 4)
                            }
                        }
                    }.listStyle(.insetGrouped)
                }
            }
            .navigationTitle(language.text("Files", "Fichiers"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                        .disabled(store.isUploading)
                }
            }
            .task { await store.refresh() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await store.protect(urls, language: language) } }
            }
            .fileExporter(isPresented: $showExporter, document: exportURL.map { ExportedLiberonsFile(url: $0) }, contentType: exportType, defaultFilename: exportURL?.lastPathComponent ?? "Libérons") { _ in
                if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
                self.exportURL = nil
            }
        }
    }

    private var exportType: UTType { exportURL.flatMap { UTType(filenameExtension: $0.pathExtension) } ?? .data }
    private func icon(for item: ProtectedFileItem) -> String {
        let ext = (item.originalFilename ?? "").split(separator: ".").last?.lowercased() ?? ""
        if ext == "pdf" { return "doc.richtext.fill" }
        if ["zip","rar","7z"].contains(ext) { return "doc.zipper" }
        if ["mp3","wav","m4a","aac"].contains(ext) { return "waveform" }
        return "doc.fill"
    }
    private func restore(_ item: ProtectedFileItem) async {
        downloadingID = item.id
        defer { downloadingID = nil }
        do {
            exportURL = try await store.download(item)
            showExporter = true
        } catch { }
    }
}

struct ExportedLiberonsFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .item] }
    let url: URL
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try FileWrapper(url: url, options: .immediate) }
}
