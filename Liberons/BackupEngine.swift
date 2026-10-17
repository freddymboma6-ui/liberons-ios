import Foundation
import Combine
import Photos
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class BackupEngine: ObservableObject {
    @Published private(set) var isRunning=false
    @Published private(set) var message=""
    @Published private(set) var selectedLocalIdentifier:String?
    @Published private(set) var selectedFilename:String?
    @Published private(set) var selectedBytes:Int64=0
    @Published private(set) var selectedIsVideo=false
    @Published private(set) var selectedCreationDate:Date?
    @Published private(set) var lastProtectedLocalIdentifier:String?
    @Published private(set) var lastProtectedFilename:String?
    @Published private(set) var lastProtectedBytes:Int64=0
    @Published private(set) var lastProtectedIsVideo=false
    @Published private(set) var newlyProtectedLocalIdentifiers:[String]=[]
    @Published private(set) var protectionBatchID=UUID()
    @Published private(set) var queueTotal=0
    @Published private(set) var queueCompleted=0
    @Published private(set) var queueFailed=0
    @Published private(set) var currentQueueFilename:String?
    @Published private(set) var activeTransfers=0
    @Published private(set) var maxConcurrentTransfers=1

    private var selectionConfirmed=false
    var queueProgress:Double{queueTotal==0 ? 0:Double(queueCompleted+queueFailed)/Double(queueTotal)}
    var queueRemaining:Int{max(0,queueTotal-queueCompleted-queueFailed)}
    var queuePercent:Int{Int((queueProgress*100).rounded())}

    private struct InitiateResponse:Decodable{struct Upload:Decodable{let url:String;let headers:[String:String]};let asset_id:String;let upload_session_id:String;let upload:Upload}
    private struct ProtectedResult:Sendable{let localIdentifier:String;let filename:String;let bytes:Int64;let isVideo:Bool}

    func prepareOldestAsset(){let options=PHFetchOptions();options.sortDescriptors=[NSSortDescriptor(key:"creationDate",ascending:true)];options.fetchLimit=1;guard let asset=PHAsset.fetchAssets(with:options).firstObject,let resource=PHAssetResource.assetResources(for:asset).first else{selectedLocalIdentifier=nil;selectedFilename=nil;message="No media found";return};setPreview(asset:asset,resource:resource);selectionConfirmed=true;message="Oldest item ready — tap again to protect"}
    func backupSelectedAsset()async{guard !isRunning else{return};guard let id=selectedLocalIdentifier else{message="Select media first";return};await backup(localIdentifiers:[id])}
    func backupOneOldestAsset()async{if !selectionConfirmed{prepareOldestAsset();return};selectionConfirmed=false;await backupSelectedAsset()}
    func backupItems(count:Int,newestFirst:Bool)async{guard count>0 else{return};let options=PHFetchOptions();options.sortDescriptors=[NSSortDescriptor(key:"creationDate",ascending:!newestFirst)];options.fetchLimit=count;let result=PHAsset.fetchAssets(with:options);var ids:[String]=[];result.enumerateObjects{asset,_,_ in ids.append(asset.localIdentifier)};await backup(localIdentifiers:ids)}
    func backupOldestItems(count:Int)async{await backupItems(count:count,newestFirst:false)}
    func backupMemories(localIdentifiers:[String],count:Int,newestFirst:Bool)async{guard count>0 else{return};let result=PHAsset.fetchAssets(withLocalIdentifiers:localIdentifiers,options:nil);var assets:[PHAsset]=[];result.enumerateObjects{asset,_,_ in assets.append(asset)};assets.sort{let a=$0.creationDate ?? .distantPast;let b=$1.creationDate ?? .distantPast;return newestFirst ? a>b:a<b};await backup(localIdentifiers:Array(assets.prefix(count)).map(\.localIdentifier))}

    /// Runs a bounded number of complete export → upload → verify pipelines at once.
    /// This keeps the UI responsive while making good use of Wi‑Fi. We deliberately
    /// reduce pressure when Low Power Mode or thermal pressure is active.
    func backup(localIdentifiers:[String])async{
        guard !isRunning else{return}
        var seen=Set<String>()
        let unique=localIdentifiers.filter{seen.insert($0).inserted}
        let result=PHAsset.fetchAssets(withLocalIdentifiers:unique,options:nil)
        var map:[String:PHAsset]=[:]
        result.enumerateObjects{asset,_,_ in map[asset.localIdentifier]=asset}
        let assets=unique.compactMap{map[$0]}
        guard !assets.isEmpty else{message="No selected media found";return}

        newlyProtectedLocalIdentifiers=[]
        isRunning=true
        queueTotal=assets.count
        queueCompleted=0
        queueFailed=0
        maxConcurrentTransfers=recommendedConcurrency()
        activeTransfers=0
        message="Preparing \(queueTotal) items…"

        defer{
            isRunning=false
            activeTransfers=0
            currentQueueFilename=nil
            if !newlyProtectedLocalIdentifiers.isEmpty{
                protectionBatchID=UUID()
                NotificationCenter.default.post(name:.liberonsCloudDidChange,object:nil)
            }
        }

        var iterator=assets.makeIterator()
        await withTaskGroup(of:Result<ProtectedResult,Error>.self){group in
            let initial=min(maxConcurrentTransfers,assets.count)
            for _ in 0..<initial{
                if let asset=iterator.next(){
                    activeTransfers+=1
                    group.addTask{await self.protectResult(asset:asset)}
                }
            }

            while let outcome=await group.next(){
                activeTransfers=max(0,activeTransfers-1)
                switch outcome{
                case .success(let protected):
                    newlyProtectedLocalIdentifiers.append(protected.localIdentifier)
                    queueCompleted+=1
                    lastProtectedLocalIdentifier=protected.localIdentifier
                    lastProtectedFilename=protected.filename
                    lastProtectedBytes=protected.bytes
                    lastProtectedIsVideo=protected.isVideo
                case .failure:
                    queueFailed+=1
                }

                let done=queueCompleted+queueFailed
                message="\(queuePercent)% • \(queueRemaining) remaining"

                if let next=iterator.next(){
                    if let resource=PHAssetResource.assetResources(for:next).first{currentQueueFilename=resource.originalFilename}
                    activeTransfers+=1
                    group.addTask{await self.protectResult(asset:next)}
                }else if done==queueTotal{
                    currentQueueFilename=nil
                }
            }
        }

        message=queueFailed==0 ? "\(queueCompleted) items protected ✓":"\(queueCompleted) protected • \(queueFailed) failed"
    }

    func clearPostBackupOffer(){newlyProtectedLocalIdentifiers=[]}

    private func recommendedConcurrency()->Int{
        if ProcessInfo.processInfo.isLowPowerModeEnabled{return 2}
        switch ProcessInfo.processInfo.thermalState{
        case .serious,.critical:return 2
        case .fair:return 3
        default:return 4
        }
    }

    private func setPreview(asset:PHAsset,resource:PHAssetResource){selectedLocalIdentifier=asset.localIdentifier;selectedFilename=resource.originalFilename;selectedIsVideo=asset.mediaType == .video;selectedCreationDate=asset.creationDate;selectedBytes=Int64(resource.value(forKey:"fileSize") as? CLong ?? 0)}

    private func protectResult(asset:PHAsset)async->Result<ProtectedResult,Error>{
        guard let resource=PHAssetResource.assetResources(for:asset).first else{return .failure(NSError(domain:"LiberonsBackup",code:2,userInfo:[NSLocalizedDescriptionKey:"No media resource found"]))}
        do{return .success(try await protect(asset:asset,resource:resource))}catch{return .failure(error)}
    }

    private func protect(asset:PHAsset,resource:PHAssetResource)async throws->ProtectedResult{
        var temporaryURL:URL?
        defer{if let temporaryURL{try? FileManager.default.removeItem(at:temporaryURL)}}
        let ext=(resource.originalFilename as NSString).pathExtension
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        temporaryURL=temp
        try await export(resource:resource,to:temp)
        let byteCount=(try temp.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
        guard byteCount>0 else{throw NSError(domain:"LiberonsBackup",code:3,userInfo:[NSLocalizedDescriptionKey:"Exported media is empty"])}

        // Hashing large videos on the MainActor was one of the biggest UI stalls.
        // Move the file scan off the UI actor while keeping the same SHA‑256 safety check.
        let checksum=try await Task.detached(priority:.utility){try Self.sha256Detached(fileURL:temp)}.value
        let mimeType=UTType(filenameExtension:ext)?.preferredMIMEType ?? (asset.mediaType == .video ? "video/mp4":"image/jpeg")
        let iso=ISO8601DateFormatter()
        var body:[String:Any]=["filename":resource.originalFilename,"mime_type":mimeType,"size_bytes":byteCount,"checksum_sha256":checksum,"ios_local_identifier":asset.localIdentifier]
        if let captured=asset.creationDate{body["captured_at"]=iso.string(from:captured)}
        let initiateData=try await SupabaseService.callFunction("initiate-upload",json:try JSONSerialization.data(withJSONObject:body))
        let initiated=try JSONDecoder().decode(InitiateResponse.self,from:initiateData)
        guard let signedURL=URL(string:initiated.upload.url) else{throw NSError(domain:"LiberonsBackup",code:4,userInfo:[NSLocalizedDescriptionKey:"Invalid signed upload URL"])}
        try await SupabaseService.putFile(temp,to:signedURL,headers:initiated.upload.headers)
        let verifiedData=try await SupabaseService.verifyUpload(assetID:initiated.asset_id,uploadSessionID:initiated.upload_session_id)
        let verifiedObject=try JSONSerialization.jsonObject(with:verifiedData) as? [String:Any]
        guard verifiedObject?["protected"] as? Bool == true else{throw NSError(domain:"LiberonsBackup",code:5,userInfo:[NSLocalizedDescriptionKey:"Cloud copy was not marked protected"])}
        return ProtectedResult(localIdentifier:asset.localIdentifier,filename:resource.originalFilename,bytes:Int64(byteCount),isVideo:asset.mediaType == .video)
    }

    private func export(resource:PHAssetResource,to url:URL)async throws{
        try await withCheckedThrowingContinuation{(continuation:CheckedContinuation<Void,Error>) in
            let options=PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed=true
            PHAssetResourceManager.default().writeData(for:resource,toFile:url,options:options){error in
                if let error{continuation.resume(throwing:error)}else{continuation.resume(returning:())}
            }
        }
    }

    nonisolated private static func sha256Detached(fileURL:URL)throws->String{
        let handle=try FileHandle(forReadingFrom:fileURL)
        defer{try? handle.close()}
        var hasher=SHA256()
        while true{
            let data=try handle.read(upToCount:2_097_152) ?? Data()
            if data.isEmpty{break}
            hasher.update(data:data)
        }
        return hasher.finalize().map{String(format:"%02x",$0)}.joined()
    }
}
