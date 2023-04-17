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
    var bypass: Bool = false
    var bundle: String = Bundle.main.bundleIdentifier!
    
    override func broadcastAnnotated(withApplicationInfo applicationInfo: [AnyHashable : Any]) {
        print("Broadcast annotated")
        print(applicationInfo)
        bundle = applicationInfo[RPApplicationInfoBundleIdentifierKey] as! String
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        print("Broadcast starting!")
        // User has requested to start the broadcast. Setup info from the UI extension can be supplied but optional.
        DarwinNotificationCenter.shared.postNotification(DarwinNotification.Name("io.cyte.ios.broadcast-start"))
        DarwinNotificationCenter.shared.addObserver(self, for: DarwinNotification.Name("io.cyte.ios.app-active"), using: { [weak self] (_) in
                self!.bypass = true
            })
        DarwinNotificationCenter.shared.addObserver(self, for: DarwinNotification.Name("io.cyte.ios.app-resigned"), using: { [weak self] (_) in
                self!.bypass = false
            })
    }
    
    override func broadcastPaused() {
        // User has requested to pause the broadcast. Samples will stop being delivered.
        print("Broadcast paused!")
        DarwinNotificationCenter.shared.postNotification(DarwinNotification.Name("io.cyte.ios.broadcast-end"))
    }
    
    override func broadcastResumed() {
        // User has requested to resume the broadcast. Samples delivery will resume.
        print("Broadcast resumed!")
        DarwinNotificationCenter.shared.postNotification(DarwinNotification.Name("io.cyte.ios.broadcast-start"))
    }
    
    override func broadcastFinished() {
        // User has requested to finish the broadcast.
        print("Broadcast finished!")
        DarwinNotificationCenter.shared.postNotification(DarwinNotification.Name("io.cyte.ios.broadcast-end"))
        DarwinNotificationCenter.shared.removeObserver(self)
        DispatchQueue.main.sync {
            Memory.shared.closeEpisode()
        }
        Thread.sleep(forTimeInterval: 2)
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
            switch sampleBufferType {
            case RPSampleBufferType.video:
                if (Date().timeIntervalSinceReferenceDate - lastFrameTime.timeIntervalSinceReferenceDate) < 2.0 || bypass == true {
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

extension UIImage {
    public convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        guard let cgImage = cgImage else {
            return nil
        }

        self.init(cgImage: cgImage)
    }
}
