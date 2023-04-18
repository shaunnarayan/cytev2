//
//  SampleHandler.swift
//  extension
//
//  Created by Shaun Narayan on 16/04/23.
//

import ReplayKit
import Combine
import VideoToolbox
import XCGLogger

let log = XCGLogger.default

class SampleHandler: RPBroadcastSampleHandler {
    
    var lastFrameTime: Date = Date()
    var bundle: String = Bundle.main.bundleIdentifier!
    
//    override func beginRequest(with context: NSExtensionContext) {
//        print("Begin request")
//        context.loadBroadcastingApplicationInfo(completion: { bundleId, bundleName, icon in
//            self.bundle = bundleId
//            print("Started with bundle: \(self.bundle)")
//            super.beginRequest(with: context)
//        })
//    }
    
    override func broadcastAnnotated(withApplicationInfo applicationInfo: [AnyHashable : Any]) {
        print("Broadcast annotated")
        print(applicationInfo)
        bundle = applicationInfo[RPApplicationInfoBundleIdentifierKey] as! String
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        print("Broadcast starting!")
        // User has requested to start the broadcast. Setup info from the UI extension can be supplied but optional.
    }
    
    override func broadcastPaused() {
        // User has requested to pause the broadcast. Samples will stop being delivered.
        print("Broadcast paused!")
    }
    
    override func broadcastResumed() {
        // User has requested to resume the broadcast. Samples delivery will resume.
        print("Broadcast resumed!")
    }
    
    override func broadcastFinished() {
        // User has requested to finish the broadcast.
        print("Broadcast finished!")
        DispatchQueue.main.sync {
            Memory.shared.closeEpisode()
        }
        Thread.sleep(forTimeInterval: 2)
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
            switch sampleBufferType {
            case RPSampleBufferType.video:
                if (Date().timeIntervalSinceReferenceDate - lastFrameTime.timeIntervalSinceReferenceDate) < 2.0 {
                    return
                }
                if CMSampleBufferDataIsReady(sampleBuffer)
                {
                    lastFrameTime = Date()
                    let bundle_id = bundle
                    DispatchQueue.main.sync {
                        Memory.shared.updateActiveContext(windowTitles: [:], bundleId: bundle_id)
                        let frame = CapturedFrame(surface: nil, data: sampleBuffer.imageBuffer, contentRect: CGRect(), contentScale: 0, scaleFactor: 0)
                        Memory.shared.addFrame(frame: frame, secondLength: Int64(Memory.secondsBetweenFrames))
                    }
                }
                break
            case RPSampleBufferType.audioApp:
                // Handle audio sample buffer for app audio
                break
            case RPSampleBufferType.audioMic:
                // Handle audio sample buffer for mic audio
                break
            @unknown default:
                // Handle other sample buffer types
                fatalError("Unknown type of sample buffer")
            }
    }
}
