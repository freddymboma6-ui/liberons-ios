import Foundation
import Security

enum FreeTierProtection {
    private static let service = "com.liberons.free-tier"
    private static let account = "installation-id"

    /// Stable across normal launches and app updates. Kept in Keychain instead of
    /// UserDefaults so simply clearing preferences does not mint another free-tier identity.
    static func installationID() throws -> String {
        if let existing = readKeychain(), !existing.isEmpty { return existing }
        let created = UUID().uuidString.lowercased()
        try writeKeychain(created)
        return created
    }

    /// Claims/validates the free tier on the server. The raw installation identifier
    /// is never persisted by Supabase; the Edge Function stores a server-side hash.
    static func validateFreeTier() async throws -> Bool {
        let id = try installationID()
        let body = try JSONSerialization.data(withJSONObject: ["installation_id": id])
        do {
            let data = try await SupabaseService.callFunction("claim-free-tier", json: body)
            struct Response: Decodable { let eligible: Bool }
            return try JSONDecoder().decode(Response.self, from: data).eligible
        } catch let error as NSError where error.domain == "LiberonsCloud" && error.code == 409 {
            return false
        }
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String) throws {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
