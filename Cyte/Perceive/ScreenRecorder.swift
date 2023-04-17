/*
 Copyright © 2022 Apple Inc.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Abstract:
A model object that provides the interface to capture screen content and system audio.
*/

import Foundation
#if os(macOS)
    import ScreenCaptureKit
#endif
import Combine
import OSLog
import SwiftUI
import CoreGraphics

@MainActor
class ScreenRecorder: ObservableObject {
    static let shared = ScreenRecorder()
    
    @Published var isRunning = false
#if os(macOS)
    /// The supported capture types.
    enum CaptureType {
        case display
        case window
    }
    
    private let logger = Logger()
    
    // MARK: - Video Properties
    @Published var captureType: CaptureType = .display {
        didSet { updateEngine() }
    }
    
    @Published var selectedDisplay: SCDisplay? {
        didSet { updateEngine() }
    }
    
    @Published var selectedWindow: SCWindow? {
        didSet { updateEngine() }
    }
    
    @Published var isAppExcluded = true {
        didSet { updateEngine() }
    }
    
    @Published var contentSize = CGSize(width: 1, height: 1)
    private var scaleFactor: Int { Int(NSScreen.main?.backingScaleFactor ?? 2) }
    
    @Published private(set) var availableApps = [SCRunningApplication]()
    @Published private(set) var availableDisplays = [SCDisplay]()
    @Published private(set) var availableWindows = [SCWindow]()
    
    // MARK: - Audio Properties
    @Published var isAudioCaptureEnabled = false {
        didSet {
            updateEngine()
        }
    }
    @Published var isAppAudioExcluded = false { didSet { updateEngine() } }

    // A value that specifies how often to retrieve calculated audio levels.
    private let audioLevelRefreshRate: TimeInterval = 0.1
    private var audioMeterCancellable: AnyCancellable?
    
    // The object that manages the SCStream.
    private let captureEngine = CaptureEngine()
    
    private var isSetup = false
    
    // Combine subscribers.
    private var subscriptions = Set<AnyCancellable>()
#endif
    var canRecord: Bool {
        get async {
            do {
#if os(macOS)
                // If the app doesn't have Screen Recording permission, this call generates an exception.
                try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
#else
#endif
                return true
            } catch {
                return false
            }
        }
    }
    
    /// Starts capturing screen content.
    func start() async {
        // Exit early if already running.
        guard !isRunning else { return }
#if os(macOS)
        if !isSetup {
            // Starting polling for available screen content.
            await monitorAvailableContent()
            isSetup = true
        }
        
        // Create the video capture context
        do {
            let config = streamConfiguration
            let filter = contentFilter
            
            // Update the running state.
            isRunning = true
            // Start the stream and await new video frames.
            for try await frame in captureEngine.startCapture(configuration: config, filter: filter) {
                Memory.shared.updateActiveContext(windowTitles: Dictionary(self.availableWindows.map{ ($0.owningApplication!.bundleIdentifier, $0.title ?? "") }, uniquingKeysWith: { (first, _) in first }))
                Memory.shared.addFrame(frame: frame, secondLength: Int64(Memory.secondsBetweenFrames))
                
                if contentSize != frame.size {
                    // Update the content size if it changed.
                    contentSize = frame.size
                }
            }
        } catch {
            logger.error("\(error.localizedDescription)")
            // Unable to start the stream. Set the running state to false.
            isRunning = false
        }
#else
        isRunning = true
#endif
    }
    
    /// Stops capturing screen content.
    func stop() async {
        guard isRunning else { return }
#if os(macOS)
        await captureEngine.stopCapture()
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions.removeAll()
        isSetup = false
#else
#endif
        Memory.shared.closeEpisode()
        isRunning = false
    }
    
#if os(macOS)
    func monitorAvailableContent() async {
        guard !isSetup else { return }
        // Refresh the lists of capturable content.
        await self.refreshAvailableContent()
        Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            // Memory is marked as MainActor and I suspect that enforces some global context
            Task {
                if Memory.shared.currentContext != Bundle.main.bundleIdentifier {
                    await self.refreshAvailableContent()
                    if let screenNumber = NSScreen.main!.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID {
                            for screen in self.availableDisplays {
                                if screen.displayID == screenNumber && self.selectedDisplay != screen {
                                    log.info("Matched display \(screenNumber), updating...")
                                    self.selectedDisplay = screen
                                }
                            }
                        }
                }
            }
        }
        .store(in: &subscriptions)
    }
    
    /// - Tag: UpdateCaptureConfig
    private func updateEngine() {
        guard isRunning else { return }
        Task {
            await captureEngine.update(configuration: streamConfiguration, filter: contentFilter)
        }
    }
    
    /// - Tag: UpdateFilter
    private var contentFilter: SCContentFilter {
        let filter: SCContentFilter
        switch captureType {
        case .display:
            guard let display = selectedDisplay else { fatalError("No display selected.") }
            var excludedApps = [SCRunningApplication]()
            // If a user chooses to exclude the app from the stream,
            // exclude it by matching its bundle identifier.
            if isAppExcluded {
                excludedApps = availableApps.filter { app in
                    if Bundle.main.bundleIdentifier == app.bundleIdentifier || app.bundleIdentifier.count == 0 { return true }
                    let exclusion = Memory.shared.getOrCreateBundleExclusion(name: app.bundleIdentifier)
                    return exclusion.excluded
                }
            }
            // Create a content filter with excluded apps.
            filter = SCContentFilter(display: display,
                                     excludingApplications: excludedApps,
                                     exceptingWindows: [])
        case .window:
            guard let window = selectedWindow else { fatalError("No window selected.") }
            
            // Create a content filter that includes a single window.
            filter = SCContentFilter(desktopIndependentWindow: window)
        }
        return filter
    }
    
    private var streamConfiguration: SCStreamConfiguration {
        
        let streamConfig = SCStreamConfiguration()
        
        // Configure audio capture.
        streamConfig.capturesAudio = isAudioCaptureEnabled
        streamConfig.excludesCurrentProcessAudio = isAppAudioExcluded
        
        // Configure the display content width and height.
        if captureType == .display, let display = selectedDisplay {
            streamConfig.width = display.width * scaleFactor
            streamConfig.height = display.height * scaleFactor
        }
        
        // Configure the window content width and height.
        if captureType == .window, let window = selectedWindow {
            streamConfig.width = Int(window.frame.width) * 2
            streamConfig.height = Int(window.frame.height) * 2
        }
        
        // Set the capture interval at 0.5 fps.
        streamConfig.minimumFrameInterval = CMTime(value: CMTimeValue(Memory.secondsBetweenFrames), timescale: 1)

        return streamConfig
    }
    
    /// - Tag: GetAvailableContent
    private func refreshAvailableContent() async {
        do {
            // Retrieve the available screen content to capture.
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                        onScreenWindowsOnly: true)
            availableDisplays = availableContent.displays
            
            let windows = filterWindows(availableContent.windows)
            if windows != availableWindows {
                availableWindows = windows
            }
            availableApps = availableContent.applications
            
            if selectedDisplay == nil {
                selectedDisplay = availableDisplays.first
            }
            if selectedWindow == nil {
                selectedWindow = availableWindows.first
            }
        } catch {
            logger.error("Failed to get the shareable content: \(error.localizedDescription)")
        }
    }
    
    private func filterWindows(_ windows: [SCWindow]) -> [SCWindow] {
        windows
        // Sort the windows by app name.
            .sorted { $0.owningApplication?.applicationName ?? "" < $1.owningApplication?.applicationName ?? "" }
        // Remove windows that don't have an associated .app bundle.
            .filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "" }
        // Remove this app's window from the list.
            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
    }
#endif
}
#if os(macOS)
extension SCWindow {
    var displayName: String {
        switch (owningApplication, title) {
        case (.some(let application), .some(let title)):
            return "\(application.applicationName): \(title)"
        case (.none, .some(let title)):
            return title
        case (.some(let application), .none):
            return "\(application.applicationName): \(windowID)"
        default:
            return ""
        }
    }
}

extension SCDisplay {
    var displayName: String {
        "Display: \(width) x \(height)"
    }
}
#endif
