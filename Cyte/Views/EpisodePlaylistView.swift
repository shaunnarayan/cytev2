//
//  EpisodePlaylistView.swift
//  Cyte
//
//  Created by Shaun Narayan on 13/03/23.
//

import Foundation
import SwiftUI
import Charts
import AVKit
import Combine
import Vision
import CoreData

struct EpisodePlaylistView: View {
    @EnvironmentObject var bundleCache: BundleCache
    @EnvironmentObject var episodeModel: EpisodeModel
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    
    @State var player: AVPlayer?
    @State private var thumbnailImages: [CGImage?] = []
#if os(macOS)
    @State static var windowLengthInSeconds: Int = 60 * 2
#else
    @State static var windowLengthInSeconds: Int = 30
#endif
    @State var secondsOffsetFromLastEpisode: Double
    
    @State var filter: String
    
    @State private var lastKnownInteractionPoint: CGPoint = CGPoint()
    @State private var lastX: CGFloat = 0.0
    
    @State var highlight: [CGRect] = []
    @State private var genTask: Task<(), Never>? = nil
    
    private let timelineSize: CGFloat = 16
    
    @State var documents: [Document] = []
    
    func loadDocuments() {
        documents = []
        let active_interval = episodeModel.activeInterval(at: secondsOffsetFromLastEpisode)
        if active_interval.0 == nil { return }
        let docFetch : NSFetchRequest<Document> = Document.fetchRequest()
        let offset = active_interval.1 - secondsOffsetFromLastEpisode
        let pin = active_interval.0!.episode.start!.addingTimeInterval(offset)
        docFetch.predicate = NSPredicate(format: "start <= %@ AND end >= %@", pin as CVarArg, pin as CVarArg)
        do {
            let docs = try PersistenceController.shared.container.viewContext.fetch(docFetch)
            var paths = Set<URL>()
            // @todo sort and pick closest doc by [(pin-end) < 0][0]
            for doc in docs {
                if !paths.contains(doc.path!) {
                    documents.append(doc)
                    paths.insert(doc.path!)
                }
            }
        } catch {
            print(error)
        }
    }
    
    func generateThumbnails(numThumbs: Int = 1) async {
        if episodeModel.appIntervals.count == 0 { return }
        highlight.removeAll()
        let start: Double = secondsOffsetFromLastEpisode
        let end: Double = secondsOffsetFromLastEpisode + Double(EpisodePlaylistView.windowLengthInSeconds)
        let slide = EpisodePlaylistView.windowLengthInSeconds / numThumbs
        let times = stride(from: start, to: end, by: Double(slide)).reversed()
        thumbnailImages.removeAll()
        for time in times {
            // get the AppInterval at this time, load the asset and find offset
            let active_interval = episodeModel.activeInterval(at: time)
            if active_interval.0 == nil || active_interval.0!.episode.title!.count == 0 {
                // placeholder thumb
                thumbnailImages.append(nil)
            } else {
                let asset = AVAsset(url: urlForEpisode(start: active_interval.0!.episode.start, title: active_interval.0!.episode.title))
                
                let generator = AVAssetImageGenerator(asset: asset)
                generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 1);
                generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 1);
                do {
                    // turn the absolute time into a relative offset in the episode
                    let offset = active_interval.1 - secondsOffsetFromLastEpisode
                    try thumbnailImages.append( generator.copyCGImage(at: CMTime(seconds: offset, preferredTimescale: 1), actualTime: nil) )
                } catch {
                    log.warning("Failed to generate thumbnail! \(error)")
                }
            }
        }
        if thumbnailImages.count > 0 && thumbnailImages.last! != nil && filter.count > 0 {
            // Run through vision and store results
            let requestHandler = VNImageRequestHandler(cgImage: thumbnailImages.last!!, orientation: .up)
            let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
            if !utsname.isAppleSilicon {
                // fallback for intel
                request.recognitionLevel = .fast
            }
            do {
                // Perform the text-recognition request.
                try requestHandler.perform([request])
            } catch {
                log.warning("Unable to perform the requests: \(error).")
            }
        }
        loadDocuments()
    }
    
    func recognizeTextHandler(request: VNRequest, error: Error?) {
        highlight.removeAll()
        let recognizedStringsAndRects = procVisionResult(request: request, error: error, minConfidence: 0.0)
        recognizedStringsAndRects.forEach { data in
            if data.0.lowercased().contains((episodeModel.filter.lowercased())) {
                highlight.append(data.1)
            }
        }
    }
    
    ///
    /// Given the user drag gesture, translate the view window by time interval given pixel counts
    ///
    func updateDisplayInterval(proxy: ChartProxy, geometry: GeometryProxy, gesture: DragGesture.Value) {
        if lastKnownInteractionPoint != gesture.startLocation {
            lastX = gesture.startLocation.x
            lastKnownInteractionPoint = gesture.startLocation
        }
        let chartWidth = geometry.size.width
        let deltaX = gesture.location.x - lastX
        lastX = gesture.location.x
        let xScale = CGFloat(EpisodePlaylistView.windowLengthInSeconds * 15) / chartWidth
        let deltaSeconds = Double(deltaX) * xScale * 2
        
        let newStart = secondsOffsetFromLastEpisode + deltaSeconds
        if newStart > 0 && newStart < ((episodeModel.appIntervals.last!.offset + episodeModel.appIntervals.last!.length)) {
            secondsOffsetFromLastEpisode = newStart
        }
        updateData()
    }
    
    func urlOfCurrentlyPlayingInPlayer(player : AVPlayer) -> URL? {
        return ((player.currentItem?.asset) as? AVURLAsset)?.url
    }
    
    func updateData() {
        let active_interval = episodeModel.activeInterval(at: secondsOffsetFromLastEpisode)
        
        // generate thumbs
        if genTask != nil && !genTask!.isCancelled {
            genTask!.cancel()
        }
        genTask = Task {
            // debounce to 600ms
            do {
                try await Task.sleep(nanoseconds: 600_000_000)
                await self.generateThumbnails()
            } catch { }
        }
        
        if active_interval.0 == nil || active_interval.0!.episode.title!.count == 0 || player == nil {
            return
        }
        // reset the AVPlayer to the new asset
        let current_url = urlOfCurrentlyPlayingInPlayer(player: player!)
        let new_url = urlForEpisode(start: active_interval.0!.episode.start, title: active_interval.0!.episode.title)
        if current_url != new_url {
            player = AVPlayer(url: new_url)
        }
        // seek to correct offset
        let progress = (active_interval.1) - secondsOffsetFromLastEpisode
        let offset: CMTime = CMTime(seconds: progress, preferredTimescale: player!.currentTime().timescale)
        self.player!.seek(to: offset, toleranceBefore: CMTime(value: 1, timescale: 1), toleranceAfter: CMTime(value: 1, timescale: 1))
    }
    
    func windowOffsetToCenter(of: AppInterval) -> Double {
        // I know this is really poorly written. I'm tired. I'll fix it when I see it again.
        let interval_center = (startTimeForEpisode(interval: of) + endTimeForEpisode(interval: of)) / 2.0
        let window_length = Double(EpisodePlaylistView.windowLengthInSeconds)
        let portion = interval_center / window_length
        return portion
    }
    
    func startTimeForEpisode(interval: AppInterval) -> Double {
        return max(Double(secondsOffsetFromLastEpisode) + (Double(EpisodePlaylistView.windowLengthInSeconds) - interval.offset - interval.length), 0.0)
    }
    
    func endTimeForEpisode(interval: AppInterval) -> Double {
        let end =  min(Double(EpisodePlaylistView.windowLengthInSeconds), Double(secondsOffsetFromLastEpisode) + Double(EpisodePlaylistView.windowLengthInSeconds) - Double(interval.offset))
        return end
    }
    
    func activeTime() -> String {
        let active_interval = episodeModel.activeInterval(at: secondsOffsetFromLastEpisode)
        if active_interval.0 == nil || player == nil {
            return Date().formatted()
        }
        return Date(timeIntervalSinceReferenceDate: active_interval.0!.episode.start!.timeIntervalSinceReferenceDate + player!.currentTime().seconds).formatted()
    }
    
    ///
    /// Calculates the delta between now and the active playhead location, then formats
    /// the result for display
    ///
    func humanReadableOffset() -> String {
        if episodeModel.appIntervals.count == 0 {
            return ""
        }
        let active_interval = episodeModel.activeInterval(at: secondsOffsetFromLastEpisode)
        
        let progress = active_interval.1 - secondsOffsetFromLastEpisode
        let anchor = Date().timeIntervalSinceReferenceDate - ((active_interval.0 ?? episodeModel.appIntervals.last)!.episode.end!.timeIntervalSinceReferenceDate)
        let seconds = max(1, anchor - progress)
        return "\(secondsToReadable(seconds: seconds)) ago"
    }
    
    
    var chart: some View {
        Chart {
            ForEach(episodeModel.appIntervals.filter { interval in
                return startTimeForEpisode(interval: interval) <= Double(EpisodePlaylistView.windowLengthInSeconds) &&
                endTimeForEpisode(interval: interval) >= 0
            }) { (interval: AppInterval) in
                BarMark(
                    xStart: .value("Start Time", startTimeForEpisode(interval: interval)),
                    xEnd: .value("End Time", endTimeForEpisode(interval: interval)),
                    y: .value("?", 0),
                    height: MarkDimension(floatLiteral: timelineSize * 2)
                )
                .foregroundStyle(bundleCache.getColor(bundleID: interval.episode.bundle!) ?? Color.gray)
                .cornerRadius(40.0)
            }
        }
        .frame(height: timelineSize * 4)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                Task {
                                    updateDisplayInterval(proxy: proxy, geometry: geometry, gesture: gesture)
                                }
                            }
                    )
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .onAppear {
            Task {
                updateData()
            }
        }
    }
    
    var body: some View {
        GeometryReader { metrics in
            VStack {
                VStack {
                    ZStack(alignment: .topLeading) {
#if os(macOS)
                        let width = (metrics.size.height - 100.0) / 9.0 * 16.0
                        let height = metrics.size.height - 100.0
#else
                        let width = (metrics.size.height - 100.0) / 19.5 * 9.0
                        let height = metrics.size.height - 100.0
#endif
                        VideoPlayer(player: player, videoOverlay: {
                            Rectangle()
                                .fill(highlight.count == 0 ? .clear : Color.black.opacity(0.5))
                                .cutout(
                                    highlight.map { high in
                                        RoundedRectangle(cornerRadius: 4)
                                            .scale(x: high.width * 1.2, y: high.height * 1.2)
                                            .offset(x:-(width/2) + (high.midX * width), y:(height/2) - (high.midY * height))
                                    }

                                )
                        })
                        .frame(width: width, height: height)
                    }
                }
#if os(macOS)
                .contextMenu {
                    Button {
                        let active_interval = episodeModel.activeInterval(at: secondsOffsetFromLastEpisode)
                        let url = urlForEpisode(start: active_interval.0?.episode.start!, title: active_interval.0?.episode.title!).deletingLastPathComponent()
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path(percentEncoded: false))
                    } label: {
                        Label("Reveal in Finder", systemImage: "questionmark.folder")
                    }
                }
#endif
                .accessibilityLabel("A large video preview pinned to the current slider time")
                
                ZStack {
                    GeometryReader { metrics in
                        chart
                        Group {
                            ForEach(episodeModel.appIntervals.filter { interval in
                                return startTimeForEpisode(interval: interval) <= Double(EpisodePlaylistView.windowLengthInSeconds) &&
                                endTimeForEpisode(interval: interval) >= 0
                            }) { interval in
                                PortableImage(uiImage: bundleCache.getIcon(bundleID: interval.episode.bundle!))
                                    .frame(width: timelineSize * 2, height: timelineSize * 2)
                                    .id(interval.episode.start)
                                    .offset(CGSize(width: (windowOffsetToCenter(of:interval) * metrics.size.width) - timelineSize, height: 0))
                            }
                        }
                        .frame(height: timelineSize * 4)
                        .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("A slider visually displaying segments for each application/website used, using a colored bar with icon overlay. Drag to move in time.")
                HStack(alignment: .top) {
                    Text(activeTime())
                    Group {
                        Button(action: { secondsOffsetFromLastEpisode += 2.0; updateData(); }) {}
                            .keyboardShortcut(.leftArrow, modifiers: [])
                        Button(action: { secondsOffsetFromLastEpisode = max(0.0, secondsOffsetFromLastEpisode - 2.0); updateData(); }) {}
                            .keyboardShortcut(.rightArrow, modifiers: [])
                        Button(action: { secondsOffsetFromLastEpisode = 0; updateData(); }) {}
                            .keyboardShortcut(.return, modifiers: [])
                        Button(action: { if player == nil { return }; player!.isPlaying ? player!.pause() : player!.play(); }) {}
                            .keyboardShortcut(.space, modifiers: [])
                    }.frame(maxWidth: 0, maxHeight: 0).opacity(0)
                    Text(humanReadableOffset())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: 10)
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0))
                .font(Font.caption)
                
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                if documents.count > 0 {
                    ToolbarItem {
                        Button("Resume") {
                            // Handle button tap here
                            openFile(path: documents.first!.path!)
                        }
                        .frame(width: 70)
                    }
                }
                ToolbarItem {
                    Button("Back", action: { self.presentationMode.wrappedValue.dismiss() })
                        .frame(width: 50)
                }
            }
        }
        .id(episodeModel.dataID)
    }
}
