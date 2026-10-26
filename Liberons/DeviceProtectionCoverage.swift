import Foundation
import Combine
import Photos
import Supabase

@MainActor
final class DeviceProtectionCoverage: ObservableObject {
    @Published private(set) var protectedOnDeviceCount = 0
    @Published private(set) var protectedMediaCount = 0
    @Published private(set) var deviceMediaCount = 0
    @Published private(set) var isLoading = false

    /// Share of all media protected in Libérons whose originals are still present
    /// in Apple Photos on this iPhone.
    var percent: Int {
        guard protectedMediaCount > 0 else { return 0 }
        return min(100, Int((Double(protectedOnDeviceCount) / Double(protectedMediaCount)) * 100.0))
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            protectedOnDeviceCount = 0
            protectedMediaCount = 0
            deviceMediaCount = 0
            return
        }

        let assets = PHAsset.fetchAssets(with: nil)
        deviceMediaCount = assets.count

        guard let session = try? await SupabaseService.client.auth.session else { return }
        let userID = session.user.id.uuidString

        struct ProtectedIdentifier: Decodable {
            let ios_local_identifier: String?
        }

        do {
            // Fetch every protected media row with pagination so the denominator is
            // the complete Libérons protected library, not Supabase's default page.
            let pageSize = 1_000
            var offset = 0
            var protectedIdentifiers = Set<String>()
            var totalProtected = 0

            while true {
                let rows: [ProtectedIdentifier] = try await SupabaseService.client
                    .from("media_assets")
                    .select("ios_local_identifier")
                    .eq("user_id", value: userID)
                    .eq("status", value: "protected")
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value

                totalProtected += rows.count
                for row in rows {
                    if let identifier = row.ios_local_identifier, !identifier.isEmpty {
                        protectedIdentifiers.insert(identifier)
                    }
                }

                if rows.count < pageSize { break }
                offset += pageSize
            }

            protectedMediaCount = totalProtected

            guard assets.count > 0, totalProtected > 0 else {
                protectedOnDeviceCount = 0
                return
            }

            // Compare the current Apple Photos library with the protected Libérons
            // identifiers. This tells us how many protected originals still occupy
            // space in this iPhone's photo library.
            var stillOnDevice = 0
            for index in 0..<assets.count {
                if protectedIdentifiers.contains(assets.object(at: index).localIdentifier) {
                    stillOnDevice += 1
                }
            }
            protectedOnDeviceCount = stillOnDevice
        } catch {
            // A query failure must never produce a misleading coverage percentage.
            protectedOnDeviceCount = 0
            protectedMediaCount = 0
        }
    }
}
