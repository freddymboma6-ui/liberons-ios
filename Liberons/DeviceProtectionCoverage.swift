import Foundation
import Combine
import Photos
import Supabase

@MainActor
final class DeviceProtectionCoverage: ObservableObject {
    @Published private(set) var protectedOnDeviceCount = 0
    @Published private(set) var deviceMediaCount = 0
    @Published private(set) var isLoading = false

    var percent: Int {
        guard deviceMediaCount > 0 else { return 0 }
        return min(100, Int((Double(protectedOnDeviceCount) / Double(deviceMediaCount)) * 100.0))
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            protectedOnDeviceCount = 0
            deviceMediaCount = 0
            return
        }

        // PHFetchResult is lazy, so this does not load full media contents into memory.
        // We only retain local identifiers long enough to query matching protected rows.
        let assets = PHAsset.fetchAssets(with: nil)
        deviceMediaCount = assets.count
        guard assets.count > 0 else {
            protectedOnDeviceCount = 0
            return
        }

        guard let session = try? await SupabaseService.client.auth.session else { return }
        let userID = session.user.id.uuidString
        let batchSize = 200
        var matched = Set<String>()
        var batch: [String] = []
        batch.reserveCapacity(batchSize)

        struct ProtectedIdentifier: Decodable {
            let ios_local_identifier: String?
        }

        func fetchBatch(_ identifiers: [String]) async throws -> [ProtectedIdentifier] {
            guard !identifiers.isEmpty else { return [] }
            return try await SupabaseService.client
                .from("media_assets")
                .select("ios_local_identifier")
                .eq("user_id", value: userID)
                .eq("status", value: "protected")
                .in("ios_local_identifier", values: identifiers)
                .execute()
                .value
        }

        do {
            for index in 0..<assets.count {
                batch.append(assets.object(at: index).localIdentifier)
                if batch.count == batchSize {
                    let rows = try await fetchBatch(batch)
                    for row in rows {
                        if let identifier = row.ios_local_identifier, !identifier.isEmpty {
                            matched.insert(identifier)
                        }
                    }
                    batch.removeAll(keepingCapacity: true)
                }
            }

            if !batch.isEmpty {
                let rows = try await fetchBatch(batch)
                for row in rows {
                    if let identifier = row.ios_local_identifier, !identifier.isEmpty {
                        matched.insert(identifier)
                    }
                }
            }

            protectedOnDeviceCount = matched.count
        } catch {
            // Never turn a network/query failure into a false 100% coverage claim.
            protectedOnDeviceCount = 0
        }
    }
}
