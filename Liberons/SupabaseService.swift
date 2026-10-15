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
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "LiberonsCloud",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server response"]
            )
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Edge Function request failed"
            print("❌ Edge Function \(name) HTTP \(http.statusCode): \(message)")
            throw NSError(
                domain: "LiberonsCloud",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) — \(message)"]
            )
        }

        return data
    }

    static func putFile(_ fileURL: URL, to signedURL: URL, headers: [String: String]) async throws {
        var request = URLRequest(url: signedURL)
        request.httpMethod = "PUT"

        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await URLSession.shared.upload(
            for: request,
            fromFile: fileURL
        )

        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "LiberonsCloud",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "B2 returned an invalid response"]
            )
        }

        guard (200..<300).contains(http.statusCode) else {
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            let cleanBody = rawBody
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            print("❌ B2 UPLOAD FAILED")
            print("HTTP status: \(http.statusCode)")
            print("Response: \(cleanBody)")

            let detail = cleanBody.isEmpty ? "No response body" : cleanBody
            throw NSError(
                domain: "LiberonsCloud",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "B2 upload failed — HTTP \(http.statusCode) — \(detail)"
                ]
            )
        }

        print("✅ B2 upload succeeded — HTTP \(http.statusCode)")
    }

    static func verifyUpload(assetID: String, uploadSessionID: String) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: [
            "asset_id": assetID,
            "upload_session_id": uploadSessionID
        ])
        return try await callFunction("verify-upload", json: body)
    }
}
