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
    @Published private(set) var hasLoadedCoverage = false
    @Published private(set) var refreshFailed = false

    private let cachePrefix = "liberons.device-protection-coverage.v1."

    private struct CachedCoverage: Codable {
        let protectedOnDeviceCount: Int
        let protectedMediaCount: Int
        let deviceMediaCount: Int
    }

    /// Share of all media protected in Libérons whose originals are still present
    /// in Apple Photos on this iPhone.
    var percent: Int {
        guard protectedMediaCount > 0 else { return 0 }
        return min(100, Int((Double(protectedOnDeviceCount) / Double(protectedMediaCount)) * 100.0))
    }

    private func restoreCachedCoverage(for userID: String) {
        guard !hasLoadedCoverage,
              let data = UserDefaults.standard.data(forKey: cachePrefix + userID.lowercased()),
              let cached = try? JSONDecoder().decode(CachedCoverage.self, from: data) else { return }
        protectedOnDeviceCount = max(0, cached.protectedOnDeviceCount)
        protectedMediaCount = max(0, cached.protectedMediaCount)
        deviceMediaCount = max(0, cached.deviceMediaCount)
        hasLoadedCoverage = true
    }

    private func saveCoverage(for userID: String) {
        let snapshot = CachedCoverage(
            protectedOnDeviceCount: protectedOnDeviceCount,
            protectedMediaCount: protectedMediaCount,
            deviceMediaCount: deviceMediaCount
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: cachePrefix + userID.lowercased())
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let session = try? await SupabaseService.client.auth.session else {
            refreshFailed = true
            return
        }
        let userID = session.user.id.uuidString
        restoreCachedCoverage(for: userID)

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            // No Photos access means coverage cannot be measured. Do not turn an
            // unavailable measurement into a real-looking 0% value.
            refreshFailed = true
            return
        }

        let assets = PHAsset.fetchAssets(with: nil)
        let nextDeviceMediaCount = assets.count

        struct ProtectedIdentifier: Decodable {
            let ios_local_identifier: String?
        }

        do {
            // Fetch every protected media row with pagination so the denominator is
            // the complete Libérons protected library, not Supabase's default page.
            // Build the new snapshot locally and publish only after every page succeeds.
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

            var stillOnDevice = 0
            if nextDeviceMediaCount > 0 && totalProtected > 0 {
                for index in 0..<assets.count {
                    if protectedIdentifiers.contains(assets.object(at: index).localIdentifier) {
                        stillOnDevice += 1
                    }
                }
            }

            // Commit only a fully successful calculation. A transient failure on page
            // 2, 8 or 20 can therefore never overwrite a valid previous result with 0%.
            deviceMediaCount = nextDeviceMediaCount
            protectedMediaCount = totalProtected
            protectedOnDeviceCount = stillOnDevice
            hasLoadedCoverage = true
            refreshFailed = false
            saveCoverage(for: userID)
        } catch {
            // Keep the last successful in-memory/cached snapshot. Zero is reserved for
            // a genuine successful calculation that actually contains zero protected media.
            refreshFailed = true
        }
    }
}
