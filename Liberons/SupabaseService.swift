import Foundation
import Supabase

private final class LiberonsBackgroundUploader:NSObject,URLSessionDataDelegate,URLSessionTaskDelegate,@unchecked Sendable{
    static let shared=LiberonsBackgroundUploader()
    private let lock=NSLock()
    private var continuations:[Int:CheckedContinuation<(Data,URLResponse),Error>]=[:]
    private var responseData:[Int:Data]=[:]

    private lazy var session:URLSession={
        let config=URLSessionConfiguration.background(withIdentifier:"com.liberons.cloud.background-upload")
        config.sessionSendsLaunchEvents=true
        config.isDiscretionary=false
        config.waitsForConnectivity=true
        config.allowsCellularAccess=true
        config.httpMaximumConnectionsPerHost=4
        config.timeoutIntervalForResource=60*60*6
        return URLSession(configuration:config,delegate:self,delegateQueue:nil)
    }()

    func upload(fileURL:URL,request:URLRequest)async throws->(Data,URLResponse){
        try await withCheckedThrowingContinuation{continuation in
            let task=session.uploadTask(with:request,fromFile:fileURL)
            lock.lock();continuations[task.taskIdentifier]=continuation;responseData[task.taskIdentifier]=Data();lock.unlock();task.resume()
        }
    }

    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data){lock.lock();responseData[dataTask.taskIdentifier,default:Data()].append(data);lock.unlock()}
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
        lock.lock();let continuation=continuations.removeValue(forKey:task.taskIdentifier);let data=responseData.removeValue(forKey:task.taskIdentifier) ?? Data();lock.unlock()
        guard let continuation else{return};if let error{continuation.resume(throwing:error);return}
        guard let response=task.response else{continuation.resume(throwing:NSError(domain:"LiberonsCloud",code:-1,userInfo:[NSLocalizedDescriptionKey:"B2 returned an invalid response"]));return}
        continuation.resume(returning:(data,response))
    }
}

enum SupabaseService {
    static let projectURL = URL(string: "https://kzwyweglrzcnxcpxnfuf.supabase.co")!
    static let client = SupabaseClient(supabaseURL: projectURL,supabaseKey: "sb_publishable_taO9kxbl5rYmZiFvWlI75g_JZNGzv5b")

    private struct FunctionErrorBody:Decodable{let error:String?;let message:String?;let tier:String?;let retry_after_seconds:Int?}

    static func callFunction(_ name: String, json: Data) async throws -> Data {
        let session = try await client.auth.session
        let url = projectURL.appendingPathComponent("functions").appendingPathComponent("v1").appendingPathComponent(name)
        var request = URLRequest(url: url);request.httpMethod = "POST";request.httpBody = json
        request.setValue("application/json", forHTTPHeaderField: "Content-Type");request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NSError(domain: "LiberonsCloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"]) }
        guard (200..<300).contains(http.statusCode) else {
            let payload=try? JSONDecoder().decode(FunctionErrorBody.self,from:data)
            let message:String
            switch payload?.tier {
            case "payment_restricted": message="Votre paiement doit être régularisé avant de pouvoir restaurer des originaux dans Photos. Vos souvenirs restent protégés et visibles dans Libérons."
            case "payment_grace_limit": message="La limite de récupération disponible pendant votre période de grâce a été atteinte. Vos souvenirs restent protégés dans Libérons."
            case "cooldown": message="Utilisation intensive détectée. Les restaurations sont temporairement ralenties. Vos fichiers restent protégés et disponibles dans Libérons."
            default: message=payload?.message ?? payload?.error ?? "La demande n’a pas pu être effectuée."
            }
            throw NSError(domain:"LiberonsCloud",code:http.statusCode,userInfo:[NSLocalizedDescriptionKey:message,"LiberonsTier":payload?.tier ?? "","RetryAfterSeconds":payload?.retry_after_seconds ?? 0])
        }
        return data
    }

    static func cloudMediaURL(assetID: UUID, variant:String="original") async throws -> URL {
        let body = try JSONSerialization.data(withJSONObject: ["asset_id": assetID.uuidString,"variant":variant])
        let data = try await callFunction("get-media-url", json: body)
        struct Response: Decodable { let url: String }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let url = URL(string: response.url) else { throw NSError(domain: "LiberonsCloud", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid cloud media URL"]) }
        return url
    }

    static func cloudPreviewURL(assetID:UUID) async throws -> URL { try await cloudMediaURL(assetID:assetID,variant:"thumbnail") }
    static func cloudOriginalURL(assetID:UUID) async throws -> URL { try await cloudMediaURL(assetID:assetID,variant:"original") }

    static func deleteCloudMedia(assetID: UUID) async throws -> Int64 {
        let body = try JSONSerialization.data(withJSONObject: ["asset_id": assetID.uuidString]);let data = try await callFunction("delete-media", json: body)
        struct Response: Decodable { let deleted: Bool; let released_bytes: Int64 }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.deleted else { throw NSError(domain: "LiberonsCloud", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cloud media was not deleted"]) };return response.released_bytes
    }

    static func updateLocalIdentifier(assetID: UUID, localIdentifier: String) async throws {
        struct Patch: Encodable { let ios_local_identifier: String }
        _ = try await client.from("media_assets").update(Patch(ios_local_identifier: localIdentifier)).eq("id", value: assetID.uuidString).execute()
    }

    static func putFile(_ fileURL: URL, to signedURL: URL, headers: [String: String]) async throws {
        var request = URLRequest(url: signedURL);request.httpMethod = "PUT";for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data,response)=try await LiberonsBackgroundUploader.shared.upload(fileURL:fileURL,request:request)
        guard let http=response as? HTTPURLResponse else{throw NSError(domain:"LiberonsCloud",code:-1,userInfo:[NSLocalizedDescriptionKey:"B2 returned an invalid response"])}
        guard (200..<300).contains(http.statusCode) else{let rawBody=String(data:data,encoding:.utf8) ?? "";throw NSError(domain:"LiberonsCloud",code:http.statusCode,userInfo:[NSLocalizedDescriptionKey:"B2 upload failed — HTTP \(http.statusCode) — \(rawBody)"])}
    }

    static func verifyUpload(assetID: String, uploadSessionID: String) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: ["asset_id": assetID, "upload_session_id": uploadSessionID]);return try await callFunction("verify-upload", json: body)
    }
}