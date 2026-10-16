import Foundation
import Security
import DeviceCheck
import CryptoKit

enum FreeTierProtection {
    private static let service = "com.liberons.free-tier"
    private static let installationAccount = "installation-id"
    private static let appAttestKeyAccount = "app-attest-key-id"

    static func installationID() throws -> String {
        if let existing = readKeychain(account: installationAccount), !existing.isEmpty { return existing }
        let created = UUID().uuidString.lowercased()
        try writeKeychain(created, account: installationAccount)
        return created
    }

    /// Creates one Secure Enclave-backed App Attest key for this Libérons installation.
    /// The key ID survives app updates in Keychain; Apple invalidates the actual key on reinstall/restore.
    static func appAttestKeyID() async throws -> String? {
        let service = DCAppAttestService.shared
        guard service.isSupported else { return nil }
        if let existing = readKeychain(account: appAttestKeyAccount), !existing.isEmpty { return existing }
        let keyID = try await service.generateKey()
        try writeKeychain(keyID, account: appAttestKeyAccount)
        return keyID
    }

    /// Produces an Apple assertion for a server-issued, single-use challenge.
    /// Server verification must bind this assertion to the request before it is trusted.
    static func appAttestAssertion(challenge: String, payload: Data) async throws -> (keyID: String, assertion: String)? {
        guard let keyID = try await appAttestKeyID() else { return nil }
        var signed = Data(challenge.utf8)
        signed.append(payload)
        let clientDataHash = Data(SHA256.hash(data: signed))
        let assertion = try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
        return (keyID, assertion.base64EncodedString())
    }

    static func validateFreeTier() async throws -> Bool {
        let id = try installationID()
        // Installation claim remains authoritative until the server-side App Attest
        // challenge/attestation verifier is fully enabled. Never trust a client-only attestation flag.
        let body = try JSONSerialization.data(withJSONObject: ["installation_id": id])
        do {
            let data = try await SupabaseService.callFunction("claim-free-tier", json: body)
            struct Response: Decodable { let eligible: Bool }
            return try JSONDecoder().decode(Response.self, from: data).eligible
        } catch let error as NSError where error.domain == "LiberonsCloud" && error.code == 409 {
            return false
        }
    }

    private static func readKeychain(account: String) -> String? {
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

    private static func writeKeychain(_ value: String, account: String) throws {
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
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
