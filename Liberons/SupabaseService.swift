import Foundation
import Supabase

enum SupabaseService {
    static let projectURL = URL(string: "https://kzwyweglrzcnxcpxnfuf.supabase.co")!

    static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: "sb_publishable_taO9kxbl5rYmZiFvWlI75g_JZNGzv5b"
    )

    static func callFunction(_ name: String, json: Data) async throws -> Data {
        let session = try await client.auth.session
        let url = projectURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent(name)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = json
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Edge Function request failed"
            throw NSError(domain: "LiberonsCloud", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }
}
