import Foundation
import Supabase

struct ProtectedCloudMedia: Identifiable, Decodable {
    let id: UUID
    let iosLocalIdentifier: String?
    let originalFilename: String?
    let mediaType: String
    let sizeBytes: Int64
    let capturedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case iosLocalIdentifier = "ios_local_identifier"
        case originalFilename = "original_filename"
        case mediaType = "media_type"
        case sizeBytes = "size_bytes"
        case capturedAt = "captured_at"
    }
}
