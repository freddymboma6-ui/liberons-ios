import Foundation
import Combine
import Photos
import CryptoKit
import UniformTypeIdentifiers
import UIKit

private final class PhotoExportRequestBox: @unchecked Sendable {
    private let lock=NSLock()
    private var requestID:PHAssetResourceDataRequestID?
    private var cancelled=false
    func set(_ id:PHAssetResourceDataRequestID){lock.lock();requestID=id;let shouldCancel=cancelled;lock.unlock();if shouldCancel{PHAssetResourceManager.default().cancelDataRequest(id)}}
    func cancel(){lock.lock();cancelled=true;let id=requestID;lock.unlock();if let id{PHAssetResourceManager.default().cancelDataRequest(id)}}
}

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
    @Published private(set) var lastFailureReason:String?
    @Published private(set) var failureSummary:[String:Int]=[:]

    private var selectionConfirmed=false
    private var stopRequested=false
    private var backupTask:Task<Void,Never>?
    private var pauseWaiters:[CheckedContinuation<Void,Never>]=[]
    private var repeatedFailureReason:String?
    private var repeatedFailureCount=0
    private let repeatedFailureSafetyLimit=8
    var queueProgress:Double{queueTotal==0 ? 0:Double(queueCompleted+queueFailed)/Double(queueTotal)}
    var queueRemaining:Int{max(0,queueTotal-queueCompleted-queueFailed)}
    var queuePercent:Int{Int((queueProgress*100).rounded())}

    private struct InitiateResponse:Decodable{struct Upload:Decodable{let url:String;let headers:[String:String]};let asset_id:String;let upload_session_id:String;let upload:Upload}
    private struct ProtectedResult:Sendable{let localIdentifier:String;let filename:String;let bytes:Int64;let isVideo:Bool;let cloudAssetID:String}
    private struct ThumbnailJob:Sendable{let localIdentifier:String;let cloudAssetID:String}
    private struct BackupFailure:Error,Sendable{let reason:String;let diagnostic:String;let isQuotaExceeded:Bool;init(reason:String,diagnostic:String,isQuotaExceeded:Bool=false){self.reason=reason;self.diagnostic=diagnostic;self.isQuotaExceeded=isQuotaExceeded}}

    private var isFrench:Bool{UserDefaults.standard.string(forKey:"liberons.language") == "fr"}
    private var quotaExceededMessage:String{isFrench ? "Stockage Libérons plein. Vous avez atteint la capacité incluse dans votre forfait. Passez à un forfait supérieur pour continuer à protéger vos photos et vidéos." : "Libérons storage is full. You’ve reached the storage included with your plan. Upgrade your plan to continue protecting your photos and videos."}

    func prepareOldestAsset(){let options=PHFetchOptions();options.sortDescriptors=[NSSortDescriptor(key:"creationDate",ascending:true)];options.fetchLimit=1;guard let asset=PHAsset.fetchAssets(with:options).firstObject,let resource=primaryResource(for:asset) else{selectedLocalIdentifier=nil;selectedFilename=nil;message="No media found";return};setPreview(asset:asset,resource:resource);selectionConfirmed=true;message="Oldest item ready — tap again to protect"}
    func backupSelectedAsset()async{guard !isRunning else{return};guard let id=selectedLocalIdentifier else{message="Select media first";return};await backup(localIdentifiers:[id])}
    func backupOneOldestAsset()async{if !selectionConfirmed{prepareOldestAsset();return};selectionConfirmed=false;await backupSelectedAsset()}
    func backupItems(count:Int,newestFirst:Bool)async{guard count>0 else{return};let options=PHFetchOptions();options.sortDescriptors=[NSSortDescriptor(key:"creationDate",ascending:!newestFirst)];options.fetchLimit=count;let result=PHAsset.fetchAssets(with:options);var ids:[String]=[];result.enumerateObjects{asset,_,_ in ids.append(asset.localIdentifier)};await backup(localIdentifiers:ids)}
    func backupOldestItems(count:Int)async{await backupItems(count:count,newestFirst:false)}
    func backupMemories(localIdentifiers:[String],count:Int,newestFirst:Bool)async{guard count>0 else{return};let result=PHAsset.fetchAssets(withLocalIdentifiers:localIdentifiers,options:nil);var assets:[PHAsset]=[];result.enumerateObjects{asset,_,_ in assets.append(asset)};assets.sort{let a=$0.creationDate ?? .distantPast;let b=$1.creationDate ?? .distantPast;return newestFirst ? a>b:a<b};await backup(localIdentifiers:Array(assets.prefix(count)).map(\.localIdentifier))}

    func pause(){guard isRunning,!isPaused,!isStopping else{return};isPaused=true;message="Paused • \(queueRemaining) remaining";Task{await BackupLiveActivityManager.shared.update(completed:queueCompleted,failed:queueFailed,total:queueTotal,status:"Sauvegarde en pause")}}
    func resume(){guard isRunning,isPaused,!isStopping else{return};isPaused=false;let waiters=pauseWaiters;pauseWaiters.removeAll();waiters.forEach{$0.resume()};message="\(queuePercent)% • \(queueRemaining) remaining";Task{await BackupLiveActivityManager.shared.update(completed:queueCompleted,failed:queueFailed,total:queueTotal,status:"Sauvegarde en cours")}}
    func stop(){guard isRunning,!isStopping else{return};stopRequested=true;isStopping=true;isPaused=false;let waiters=pauseWaiters;pauseWaiters.removeAll();waiters.forEach{$0.resume()};backupTask?.cancel();message="Stopping active transfer…";Task{await BackupLiveActivityManager.shared.update(completed:queueCompleted,failed:queueFailed,total:queueTotal,status:"Arrêt de la sauvegarde…")}}
    private func waitIfPaused()async{guard isPaused,!stopRequested,!Task.isCancelled else{return};await withCheckedContinuation{continuation in pauseWaiters.append(continuation)}}

    func backup(localIdentifiers:[String])async{guard !isRunning else{return};let task=Task{await runBackup(localIdentifiers:localIdentifiers)};backupTask=task;await task.value;backupTask=nil}

    private func runBackup(localIdentifiers:[String])async{
        var seen=Set<String>();let unique=localIdentifiers.filter{seen.insert($0).inserted};let result=PHAsset.fetchAssets(withLocalIdentifiers:unique,options:nil);var map:[String:PHAsset]=[:];result.enumerateObjects{asset,_,_ in map[asset.localIdentifier]=asset};let assets=unique.compactMap{map[$0]};guard !assets.isEmpty else{message="No selected media found";return}
        var thumbnailJobs:[ThumbnailJob]=[]
        newlyProtectedLocalIdentifiers=[];stopRequested=false;isStopping=false;isPaused=false;isRunning=true;queueTotal=assets.count;queueCompleted=0;queueFailed=0;lastFailureReason=nil;failureSummary=[:];repeatedFailureReason=nil;repeatedFailureCount=0;maxConcurrentTransfers=recommendedConcurrency();activeTransfers=0;message="Preparing \(queueTotal) items…"
        await BackupLiveActivityManager.shared.start(total:queueTotal)
        defer{let wasStopped=stopRequested || Task.isCancelled;let completed=queueCompleted;let failed=queueFailed;let total=queueTotal;isRunning=false;isPaused=false;isStopping=false;activeTransfers=0;currentQueueFilename=nil;let waiters=pauseWaiters;pauseWaiters.removeAll();waiters.forEach{$0.resume()};if !newlyProtectedLocalIdentifiers.isEmpty{protectionBatchID=UUID();NotificationCenter.default.post(name:.liberonsCloudDidChange,object:nil)};if !wasStopped && !thumbnailJobs.isEmpty{startDeferredThumbnails(thumbnailJobs)};Task{await BackupLiveActivityManager.shared.finish(completed:completed,failed:failed,total:total,stopped:wasStopped)}}
        var iterator=assets.makeIterator()
        await withTaskGroup(of:Result<ProtectedResult,BackupFailure>.self){group in
            let initial=min(maxConcurrentTransfers,assets.count)
            for _ in 0..<initial{guard !stopRequested,!Task.isCancelled,let asset=iterator.next() else{break};activeTransfers+=1;group.addTask{await self.protectResultWithRetry(asset:asset)}}
            while let outcome=await group.next(){activeTransfers=max(0,activeTransfers-1);if Task.isCancelled || stopRequested{group.cancelAll();continue};switch outcome{case .success(let protected):newlyProtectedLocalIdentifiers.append(protected.localIdentifier);thumbnailJobs.append(ThumbnailJob(localIdentifier:protected.localIdentifier,cloudAssetID:protected.cloudAssetID));queueCompleted+=1;lastProtectedLocalIdentifier=protected.localIdentifier;lastProtectedFilename=protected.filename;lastProtectedBytes=protected.bytes;lastProtectedIsVideo=protected.isVideo;repeatedFailureReason=nil;repeatedFailureCount=0;case .failure(let failure):if failure.reason != "Transfer cancelled"{queueFailed+=1;lastFailureReason=failure.reason;failureSummary[failure.reason,default:0]+=1};if failure.isQuotaExceeded{stopRequested=true;isStopping=true;group.cancelAll();message=failure.reason}else{if repeatedFailureReason==failure.reason{repeatedFailureCount+=1}else{repeatedFailureReason=failure.reason;repeatedFailureCount=1};if repeatedFailureCount>=repeatedFailureSafetyLimit{stopRequested=true;isStopping=true;group.cancelAll();message="Stopped: \(failure.reason)"}}};await BackupLiveActivityManager.shared.update(completed:queueCompleted,failed:queueFailed,total:queueTotal,status:"Sauvegarde en cours");if stopRequested || Task.isCancelled{group.cancelAll();continue};await waitIfPaused();guard !stopRequested,!Task.isCancelled else{group.cancelAll();continue};message=isPaused ? "Paused • \(queueRemaining) remaining":"\(queuePercent)% • \(queueRemaining) remaining";if let next=iterator.next(){currentQueueFilename=friendlyMediaLabel(for:next);activeTransfers+=1;group.addTask{await self.protectResultWithRetry(asset:next)}}}
        }
        if stopRequested || Task.isCancelled{message=lastFailureReason ?? "Backup stopped • \(queueCompleted) protected"}else{message=queueFailed==0 ? "\(queueCompleted) items protected ✓":"\(queueCompleted) protected • \(queueFailed) failed • \(lastFailureReason ?? "Unknown error")"}
    }

    func clearPostBackupOffer(){newlyProtectedLocalIdentifiers=[]}
    private func recommendedConcurrency()->Int{if ProcessInfo.processInfo.isLowPowerModeEnabled{return 2};switch ProcessInfo.processInfo.thermalState{case .serious,.critical:return 2;case .fair:return 4;default:return 8}}
    private func primaryResource(for asset:PHAsset)->PHAssetResource?{let resources=PHAssetResource.assetResources(for:asset);if asset.mediaType == .video{return resources.first(where:{$0.type == .fullSizeVideo}) ?? resources.first(where:{$0.type == .video}) ?? resources.first(where:{$0.uniformTypeIdentifier.hasPrefix("public.movie") || $0.uniformTypeIdentifier.hasPrefix("public.video")}) ?? resources.first};return resources.first(where:{$0.type == .fullSizePhoto}) ?? resources.first(where:{$0.type == .photo}) ?? resources.first}
    private func friendlyMediaLabel(for asset:PHAsset)->String{if asset.mediaType == .video{return "Protection d’une vidéo…"};if asset.mediaType == .image && asset.mediaSubtypes.contains(.photoScreenshot){return "Protection d’une capture d’écran…"};return "Protection d’une photo…"}
    private func setPreview(asset:PHAsset,resource:PHAssetResource){selectedLocalIdentifier=asset.localIdentifier;selectedFilename=resource.originalFilename;selectedIsVideo=asset.mediaType == .video;selectedCreationDate=asset.creationDate;selectedBytes=Int64(resource.value(forKey:"fileSize") as? CLong ?? 0)}

    private func protectResultWithRetry(asset:PHAsset)async->Result<ProtectedResult,BackupFailure>{guard let resource=primaryResource(for:asset) else{return .failure(BackupFailure(reason:"Original media unavailable in Photos",diagnostic:"No media resource found"))};var finalError:Error?;for attempt in 1...3{if Task.isCancelled || stopRequested{return .failure(BackupFailure(reason:"Transfer cancelled",diagnostic:"Task cancelled by user"))};do{return .success(try await protect(asset:asset,resource:resource))}catch{finalError=error;let ns=error as NSError;if ns.code==413{return .failure(classify(error:error))};if Task.isCancelled || stopRequested{return .failure(BackupFailure(reason:"Transfer cancelled",diagnostic:"Task cancelled by user"))};if attempt<3{try? await Task.sleep(for:.milliseconds(500*attempt))}}};let error=finalError ?? NSError(domain:"LiberonsBackup",code:-1,userInfo:[NSLocalizedDescriptionKey:"Unknown error"]);return .failure(classify(error:error))}
    private func classify(error:Error)->BackupFailure{let ns=error as NSError;let detail=ns.localizedDescription;let lower=detail.lowercased();let reason:String;let quotaExceeded=ns.code==413 || lower.contains("quota") || (lower.contains("storage") && lower.contains("limit"));if quotaExceeded{reason=quotaExceededMessage}else if ns.domain==NSURLErrorDomain || lower.contains("network") || lower.contains("internet") || lower.contains("timed out") || lower.contains("connection"){reason="Network connection failed after 3 attempts"}else if lower.contains("unauthorized") || lower.contains("jwt") || ns.code==401{reason="Libérons session is no longer authorized"}else if lower.contains("export") || lower.contains("icloud") || ns.domain.contains("Photos"){reason="Original could not be downloaded from Photos/iCloud"}else if lower.contains("signed upload"){reason="Cloud upload authorization could not be created"}else if lower.contains("protected") || lower.contains("verify"){reason="Cloud upload completed but verification failed"}else{reason="Upload failed: \(detail)"};return BackupFailure(reason:reason,diagnostic:"\(ns.domain) \(ns.code): \(detail)",isQuotaExceeded:quotaExceeded)}

    private func protect(asset:PHAsset,resource:PHAssetResource)async throws->ProtectedResult{try Task.checkCancellation();var temporaryURL:URL?;defer{if let temporaryURL{try? FileManager.default.removeItem(at:temporaryURL)}};let ext=(resource.originalFilename as NSString).pathExtension;let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext);temporaryURL=temp;try await export(resource:resource,to:temp);try Task.checkCancellation();guard !stopRequested else{throw CancellationError()};let byteCount=(try temp.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0;guard byteCount>0 else{throw NSError(domain:"LiberonsBackup",code:3,userInfo:[NSLocalizedDescriptionKey:"Exported media is empty"])};let checksum=try await Task.detached(priority:.utility){try Task.checkCancellation();return try Self.sha256Detached(fileURL:temp)}.value;try Task.checkCancellation();guard !stopRequested else{throw CancellationError()};let mimeType=UTType(filenameExtension:ext)?.preferredMIMEType ?? (asset.mediaType == .video ? "video/mp4":"image/jpeg");let iso=ISO8601DateFormatter();var body:[String:Any]=["filename":resource.originalFilename,"mime_type":mimeType,"size_bytes":byteCount,"checksum_sha256":checksum,"ios_local_identifier":asset.localIdentifier];if let captured=asset.creationDate{body["captured_at"]=iso.string(from:captured)};let initiateData=try await SupabaseService.callFunction("initiate-upload",json:try JSONSerialization.data(withJSONObject:body));try Task.checkCancellation();guard !stopRequested else{throw CancellationError()};let initiated=try JSONDecoder().decode(InitiateResponse.self,from:initiateData);guard let signedURL=URL(string:initiated.upload.url) else{throw NSError(domain:"LiberonsBackup",code:4,userInfo:[NSLocalizedDescriptionKey:"Invalid signed upload URL"])};try await SupabaseService.putFile(temp,to:signedURL,headers:initiated.upload.headers);try Task.checkCancellation();guard !stopRequested else{throw CancellationError()};let verifiedData=try await SupabaseService.verifyUpload(assetID:initiated.asset_id,uploadSessionID:initiated.upload_session_id);let verifiedObject=try JSONSerialization.jsonObject(with:verifiedData) as? [String:Any];guard verifiedObject?["protected"] as? Bool == true else{throw NSError(domain:"LiberonsBackup",code:5,userInfo:[NSLocalizedDescriptionKey:"Cloud copy was not marked protected"])};return ProtectedResult(localIdentifier:asset.localIdentifier,filename:resource.originalFilename,bytes:Int64(byteCount),isVideo:asset.mediaType == .video,cloudAssetID:initiated.asset_id)}

    private func startDeferredThumbnails(_ jobs:[ThumbnailJob]){Task(priority:.utility){for job in jobs{if ProcessInfo.processInfo.thermalState == .critical{break};let result=PHAsset.fetchAssets(withLocalIdentifiers:[job.localIdentifier],options:nil);guard let asset=result.firstObject,let thumbnail=await self.thumbnailJPEG(for:asset) else{continue};let thumbBody:[String:Any]=["asset_id":job.cloudAssetID,"jpeg_base64":thumbnail.base64EncodedString()];_ = try? await SupabaseService.callFunction("upload-media-thumbnail",json:try JSONSerialization.data(withJSONObject:thumbBody));await Task.yield()};NotificationCenter.default.post(name:.liberonsCloudDidChange,object:nil)}}
    private func thumbnailJPEG(for asset:PHAsset)async->Data?{await withCheckedContinuation{continuation in let options=PHImageRequestOptions();options.deliveryMode = .fastFormat;options.resizeMode = .fast;options.isNetworkAccessAllowed=false;PHImageManager.default().requestImage(for:asset,targetSize:CGSize(width:360,height:360),contentMode:.aspectFill,options:options){image,info in if (info?[PHImageCancelledKey] as? Bool)==true{continuation.resume(returning:nil);return};continuation.resume(returning:image?.jpegData(compressionQuality:0.62))}}}
    private func export(resource:PHAssetResource,to url:URL)async throws{
        try Task.checkCancellation()
        FileManager.default.createFile(atPath:url.path,contents:nil)
        let handle=try FileHandle(forWritingTo:url)
        let requestBox=PhotoExportRequestBox()
        defer{try? handle.close()}
        try await withTaskCancellationHandler(operation:{
            try await withCheckedThrowingContinuation{(continuation:CheckedContinuation<Void,Error>) in
                let options=PHAssetResourceRequestOptions();options.isNetworkAccessAllowed=true
                let requestID=PHAssetResourceManager.default().requestData(for:resource,options:options,dataReceivedHandler:{data in
                    do{try handle.write(contentsOf:data)}catch{requestBox.cancel()}
                },completionHandler:{error in if let error{continuation.resume(throwing:error)}else{continuation.resume(returning:())}})
                requestBox.set(requestID)
            }
        },onCancel:{requestBox.cancel()})
        try Task.checkCancellation()
    }
    nonisolated private static func sha256Detached(fileURL:URL)throws->String{let handle=try FileHandle(forReadingFrom:fileURL);defer{try? handle.close()};var hasher=SHA256();while autoreleasepool(invoking:{let data=handle.readData(ofLength:1024*1024);if data.isEmpty{return false};hasher.update(data:data);return true}){};return hasher.finalize().map{String(format:"%02x",$0)}.joined()}
}