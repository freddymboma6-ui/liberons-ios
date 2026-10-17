import Foundation
import Combine
import Photos
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class BackupEngine: ObservableObject {
    @Published private(set) var isRunning=false
    @Published private(set) var isPaused=false
    @Published private(set) var isStopping=false
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
    private var stopRequested=false
    private var pauseWaiters:[CheckedContinuation<Void,Never>]=[]
    var queueProgress:Double{queueTotal==0 ? 0:Double(queueCompleted+queueFailed)/Double(queueTotal)}
    var queueRemaining:Int{max(0,queueTotal-queueCompleted-queueFailed)}
    var queuePercent:Int{Int((queueProgress*100).rounded())}

    private struct InitiateResponse:Decodable{struct Upload:Decodable{let url:String;let headers:[String:String]};let asset_id:String;let upload_session_id:String;let upload:Upload}
    private struct ProtectedResult:Sendable{let localIdentifier:String;let filename:String;let bytes:Int64;let isVideo:Bool}

    func prepareOldestAsset(){let options=PHFetchOptions();options.sortDescriptors=[NSSortDescriptor(key:"creationDate",ascending:true)];options.fetchLimit=1;guard let asset=PHAsset.fetchAssets(with:options).firstObject,let resource=primaryResource(for:asset) else{selectedLocalIdentifier=nil;selectedFilename=nil;message="No media found";return};setPreview(asset:asset,resource:resource);selectionConfirmed=true;message="Oldest item ready — tap again to protect"}
    func backupSelectedAsset()async{guard !isRunning else{return};guard let id=selectedLocalIdentifier else{message="Select media first";return};await backup(localIdentifiers:[id])}
    func backupOneOldestAsset()async{if !selectionConfirmed{prepareOldestAsset();return};selectionConfirmed=false;await backupSelectedAsset()}
    func backupItems(count:Int,newestFirst:Bool)async{guard count>0 else{return};let options=PHFetchOptions();options.sortDescriptors=[NSSortDescriptor(key:"creationDate",ascending:!newestFirst)];options.fetchLimit=count;let result=PHAsset.fetchAssets(with:options);var ids:[String]=[];result.enumerateObjects{asset,_,_ in ids.append(asset.localIdentifier)};await backup(localIdentifiers:ids)}
    func backupOldestItems(count:Int)async{await backupItems(count:count,newestFirst:false)}
    func backupMemories(localIdentifiers:[String],count:Int,newestFirst:Bool)async{guard count>0 else{return};let result=PHAsset.fetchAssets(withLocalIdentifiers:localIdentifiers,options:nil);var assets:[PHAsset]=[];result.enumerateObjects{asset,_,_ in assets.append(asset)};assets.sort{let a=$0.creationDate ?? .distantPast;let b=$1.creationDate ?? .distantPast;return newestFirst ? a>b:a<b};await backup(localIdentifiers:Array(assets.prefix(count)).map(\.localIdentifier))}

    func pause(){guard isRunning,!isPaused,!isStopping else{return};isPaused=true;message="Paused • \(queueRemaining) remaining"}
    func resume(){guard isRunning,isPaused,!isStopping else{return};isPaused=false;let waiters=pauseWaiters;pauseWaiters.removeAll();waiters.forEach{$0.resume()};message="\(queuePercent)% • \(queueRemaining) remaining"}
    func stop(){guard isRunning,!isStopping else{return};stopRequested=true;isStopping=true;if isPaused{isPaused=false;let waiters=pauseWaiters;pauseWaiters.removeAll();waiters.forEach{$0.resume()}};message=activeTransfers>0 ? "Stopping safely…":"Backup stopped"}
    private func waitIfPaused()async{guard isPaused,!stopRequested else{return};await withCheckedContinuation{continuation in pauseWaiters.append(continuation)}}

    func backup(localIdentifiers:[String])async{
        guard !isRunning else{return}
        var seen=Set<String>()
        let unique=localIdentifiers.filter{seen.insert($0).inserted}
        let result=PHAsset.fetchAssets(withLocalIdentifiers:unique,options:nil)
        var map:[String:PHAsset]=[:]
        result.enumerateObjects{asset,_,_ in map[asset.localIdentifier]=asset}
        let assets=unique.compactMap{map[$0]}
        guard !assets.isEmpty else{message="No selected media found";return}
        newlyProtectedLocalIdentifiers=[];stopRequested=false;isStopping=false;isPaused=false;isRunning=true;queueTotal=assets.count;queueCompleted=0;queueFailed=0;maxConcurrentTransfers=recommendedConcurrency();activeTransfers=0;message="Preparing \(queueTotal) items…"
        defer{isRunning=false;isPaused=false;isStopping=false;activeTransfers=0;currentQueueFilename=nil;let waiters=pauseWaiters;pauseWaiters.removeAll();waiters.forEach{$0.resume()};if !newlyProtectedLocalIdentifiers.isEmpty{protectionBatchID=UUID();NotificationCenter.default.post(name:.liberonsCloudDidChange,object:nil)}}
        var iterator=assets.makeIterator()
        await withTaskGroup(of:Result<ProtectedResult,Error>.self){group in
            let initial=min(maxConcurrentTransfers,assets.count)
            for _ in 0..<initial{guard !stopRequested,let asset=iterator.next() else{break};activeTransfers+=1;group.addTask{await self.protectResult(asset:asset)}}
            while let outcome=await group.next(){
                activeTransfers=max(0,activeTransfers-1)
                switch outcome{case .success(let protected):newlyProtectedLocalIdentifiers.append(protected.localIdentifier);queueCompleted+=1;lastProtectedLocalIdentifier=protected.localIdentifier;lastProtectedFilename=protected.filename;lastProtectedBytes=protected.bytes;lastProtectedIsVideo=protected.isVideo;case .failure:queueFailed+=1}
                if stopRequested{message=activeTransfers>0 ? "Stopping safely…":"Backup stopped";continue}
                await waitIfPaused();guard !stopRequested else{message=activeTransfers>0 ? "Stopping safely…":"Backup stopped";continue}
                message=isPaused ? "Paused • \(queueRemaining) remaining":"\(queuePercent)% • \(queueRemaining) remaining"
                if let next=iterator.next(){if let resource=primaryResource(for:next){currentQueueFilename=resource.originalFilename};activeTransfers+=1;group.addTask{await self.protectResult(asset:next)}}
            }
        }
        if stopRequested{message="Backup stopped • \(queueCompleted) protected"}else{message=queueFailed==0 ? "\(queueCompleted) items protected ✓":"\(queueCompleted) protected • \(queueFailed) failed"}
    }

    func clearPostBackupOffer(){newlyProtectedLocalIdentifiers=[]}

    private func recommendedConcurrency()->Int{
        if ProcessInfo.processInfo.isLowPowerModeEnabled{return 2}
        switch ProcessInfo.processInfo.thermalState{case .serious,.critical:return 2;case .fair:return 4;default:return 6}
    }

    /// Picks the actual original for the PHAsset. `assetResources.first` is not reliable:
    /// Live Photos and some imported/video assets can expose a photo/adjustment resource first.
    /// Using the matching video resource fixes videos being silently exported as the wrong file.
    private func primaryResource(for asset:PHAsset)->PHAssetResource?{
        let resources=PHAssetResource.assetResources(for:asset)
        if asset.mediaType == .video{
            return resources.first(where:{$0.type == .fullSizeVideo})
                ?? resources.first(where:{$0.type == .video})
                ?? resources.first(where:{$0.uniformTypeIdentifier.hasPrefix("public.movie") || $0.uniformTypeIdentifier.hasPrefix("public.video")})
                ?? resources.first
        }
        return resources.first(where:{$0.type == .fullSizePhoto})
            ?? resources.first(where:{$0.type == .photo})
            ?? resources.first
    }

    private func setPreview(asset:PHAsset,resource:PHAssetResource){selectedLocalIdentifier=asset.localIdentifier;selectedFilename=resource.originalFilename;selectedIsVideo=asset.mediaType == .video;selectedCreationDate=asset.creationDate;selectedBytes=Int64(resource.value(forKey:"fileSize") as? CLong ?? 0)}

    private func protectResult(asset:PHAsset)async->Result<ProtectedResult,Error>{guard let resource=primaryResource(for:asset) else{return .failure(NSError(domain:"LiberonsBackup",code:2,userInfo:[NSLocalizedDescriptionKey:"No media resource found"]))};do{return .success(try await protect(asset:asset,resource:resource))}catch{return .failure(error)}}

    private func protect(asset:PHAsset,resource:PHAssetResource)async throws->ProtectedResult{
        var temporaryURL:URL?;defer{if let temporaryURL{try? FileManager.default.removeItem(at:temporaryURL)}}
        let ext=(resource.originalFilename as NSString).pathExtension
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext);temporaryURL=temp
        try await export(resource:resource,to:temp)
        let byteCount=(try temp.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
        guard byteCount>0 else{throw NSError(domain:"LiberonsBackup",code:3,userInfo:[NSLocalizedDescriptionKey:"Exported media is empty"])}
        let checksum=try await Task.detached(priority:.utility){try Self.sha256Detached(fileURL:temp)}.value
        let mimeType=UTType(filenameExtension:ext)?.preferredMIMEType ?? (asset.mediaType == .video ? "video/mp4":"image/jpeg")
        let iso=ISO8601DateFormatter();var body:[String:Any]=["filename":resource.originalFilename,"mime_type":mimeType,"size_bytes":byteCount,"checksum_sha256":checksum,"ios_local_identifier":asset.localIdentifier];if let captured=asset.creationDate{body["captured_at"]=iso.string(from:captured)}
        let initiateData=try await SupabaseService.callFunction("initiate-upload",json:try JSONSerialization.data(withJSONObject:body));let initiated=try JSONDecoder().decode(InitiateResponse.self,from:initiateData)
        guard let signedURL=URL(string:initiated.upload.url) else{throw NSError(domain:"LiberonsBackup",code:4,userInfo:[NSLocalizedDescriptionKey:"Invalid signed upload URL"])}
        try await SupabaseService.putFile(temp,to:signedURL,headers:initiated.upload.headers)
        let verifiedData=try await SupabaseService.verifyUpload(assetID:initiated.asset_id,uploadSessionID:initiated.upload_session_id);let verifiedObject=try JSONSerialization.jsonObject(with:verifiedData) as? [String:Any]
        guard verifiedObject?["protected"] as? Bool == true else{throw NSError(domain:"LiberonsBackup",code:5,userInfo:[NSLocalizedDescriptionKey:"Cloud copy was not marked protected"])}
        return ProtectedResult(localIdentifier:asset.localIdentifier,filename:resource.originalFilename,bytes:Int64(byteCount),isVideo:asset.mediaType == .video)
    }

    private func export(resource:PHAssetResource,to url:URL)async throws{try await withCheckedThrowingContinuation{(continuation:CheckedContinuation<Void,Error>) in let options=PHAssetResourceRequestOptions();options.isNetworkAccessAllowed=true;PHAssetResourceManager.default().writeData(for:resource,toFile:url,options:options){error in if let error{continuation.resume(throwing:error)}else{continuation.resume(returning:())}}}}

    nonisolated private static func sha256Detached(fileURL:URL)throws->String{let handle=try FileHandle(forReadingFrom:fileURL);defer{try? handle.close()};var hasher=SHA256();while true{let data=try handle.read(upToCount:4_194_304) ?? Data();if data.isEmpty{break};hasher.update(data:data)};return hasher.finalize().map{String(format:"%02x",$0)}.joined()}
}
