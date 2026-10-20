import Foundation
import UIKit
import Supabase

@MainActor
final class PresenceService {
    static let shared = PresenceService()

    private var heartbeatTask: Task<Void, Never>?
    private let intervalNanoseconds: UInt64 = 35_000_000_000
    private let deviceKeyDefaultsKey = "liberons.presence.device-key"

    private init() {}

    func start() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            await self.sendHeartbeat()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.intervalNanoseconds)
                guard !Task.isCancelled else { break }
                await self.sendHeartbeat()
            }
        }
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    func sendHeartbeat() async {
        guard (try? await SupabaseService.client.auth.session) != nil else { return }

        let device = UIDevice.current
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let appVersion = build.isEmpty ? version : "\(version) (\(build))"
        let type = device.userInterfaceIdiom == .pad ? "iPad" : "iPhone"

        let payload = PresencePayload(
            device_key: persistentDeviceKey(),
            device_name: device.name,
            device_type: type,
            platform: "iOS",
            app_version: appVersion,
            os_version: "iOS \(device.systemVersion)"
        )

        do {
            let _: PresenceResponse = try await SupabaseService.client.functions
                .invoke("account-presence", options: FunctionInvokeOptions(body: payload))
        } catch {
            // Presence must never interrupt the user experience.
        }
    }

    private func persistentDeviceKey() -> String {
        if let existing = UserDefaults.standard.string(forKey: deviceKeyDefaultsKey), !existing.isEmpty {
            return existing
        }
        let created = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(created, forKey: deviceKeyDefaultsKey)
        return created
    }
}

private struct PresencePayload: Encodable {
    let device_key: String
    let device_name: String
    let device_type: String
    let platform: String
    let app_version: String
    let os_version: String
}

private struct PresenceResponse: Decodable {
    let ok: Bool
}
