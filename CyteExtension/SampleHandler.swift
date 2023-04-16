//
//  SampleHandler.swift
//  extension
//
//  Created by Shaun Narayan on 16/04/23.
//

import ReplayKit

class SampleHandler: RPBroadcastSampleHandler {
    
    var extContext: NSExtensionContext? = nil
    
    override func beginRequest(with context: NSExtensionContext) {
        print("brginRequest starting!")
        extContext = context
        super.beginRequest(with: context)
        let broadcastURL = URL(string:"https://s3-us-west-1.amazonaws.com/avplayervideo/What+Is+Cloud+Communications.mov")
        // Dictionary with setup information that will be provided to broadcast extension when broadcast is started

        let setupInfo: [String : NSCoding & NSObjectProtocol] = [:]
        
        // Tell ReplayKit that the extension is finished setting up and can begin broadcasting
        extContext?.completeRequest(withBroadcast: broadcastURL!, setupInfo: setupInfo)
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        print("Broadcast starting!")
        // User has requested to start the broadcast. Setup info from the UI extension can be supplied but optional.
//        DarwinNotificationCenter.shared.postNotification(DarwinNotification.Name("io.cyte.ios.on-start"), data: nil)
    }
    
    override func broadcastPaused() {
        // User has requested to pause the broadcast. Samples will stop being delivered.
        print("Broadcast starting!")
//        DarwinNotificationCenter.shared.postNotification(DarwinNotification.Name("io.cyte.ios.on-stop"), data: nil)
    }
    
    override func broadcastResumed() {
        // User has requested to resume the broadcast. Samples delivery will resume.
        print("Broadcast starting!")
//        DarwinNotificationCenter.shared.postNotification(DarwinNotification.Name("io.cyte.ios.on-start"), data: nil)
    }
    
    override func broadcastFinished() {
        // User has requested to finish the broadcast.
        print("Broadcast starting!")
//        DarwinNotificationCenter.shared.postNotification(DarwinNotification.Name("io.cyte.ios.on-stop"), data: nil)
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        DispatchQueue.main.sync {
            
            switch sampleBufferType {
            case RPSampleBufferType.video:
                // Handle video sample buffer
                extContext?.loadBroadcastingApplicationInfo(completion: { (bundle, name, icon) in
                    print(name)
                    guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        assertionFailure("SampleBuffer did not have an ImageBuffer")
                        return
                    }
                    
                    var frame: [String: Any] = [:]
                    frame["frame"] = sourcePixelBuffer
                    frame["bundle"] = bundle
                    frame["name"] = name
                    frame["icon"] = icon
                    DarwinNotificationCenter.shared.postNotification(DarwinNotification.Name("io.cyte.ios.on-frame"), data: frame as CFDictionary)
                })
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
}
