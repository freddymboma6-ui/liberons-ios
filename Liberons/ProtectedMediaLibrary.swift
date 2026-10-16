import Foundation
import Supabase

struct ProtectedCloudMedia: Identifiable, Decodable, Hashable {
    let id: UUID
    let iosLocalIdentifier: String?
    let originalFilename: String?
    let mediaType: String
    let sizeBytes: Int64
    let capturedAt: Date?
    let protectedAt: Date?
    let createdAt: Date
    let localRemovedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case iosLocalIdentifier = "ios_local_identifier"
        case originalFilename = "original_filename"
        case mediaType = "media_type"
        case sizeBytes = "size_bytes"
        case capturedAt = "captured_at"
        case protectedAt = "protected_at"
        case createdAt = "created_at"
        case localRemovedAt = "local_removed_at"
    }
}
