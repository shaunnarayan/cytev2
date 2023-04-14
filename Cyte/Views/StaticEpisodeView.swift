//
//  StaticEpisodeView.swift
//  Cyte
//
//  Created by Shaun Narayan on 17/03/23.
//

import Foundation
import SwiftUI
import Charts
import AVKit
import Combine
import Vision

struct StaticEpisodeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var bundleCache: BundleCache
    @EnvironmentObject var episodeModel: EpisodeModel
    
    @State var asset: AVAsset
    @ObservedObject var episode: Episode
    
    @State var selection: Int = 0
    @ObservedObject var result: CyteInterval
    @State var filter: String
    @State var highlight: [CGRect] = []
    @State var thumbnail: CGImage?
    
    @State private var isHoveringSave: Bool = false
    @State private var isHoveringExpand: Bool = false
    @State private var isHoveringNext: Bool = false
    @State var selected: Bool
    
    @State private var genTask: Task<(), Never>?
    
    func generateThumbnail(offset: Double) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 1);
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 1);
        do {
            thumbnail = try generator.copyCGImage(at: CMTime(seconds: offset, preferredTimescale: 1), actualTime: nil)
            // Run through vision and store results
            let requestHandler = VNImageRequestHandler(cgImage: thumbnail!, orientation: .up)
            let request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
//            if !utsname.isAppleSilicon {
                // fallback for intel
                request.recognitionLevel = .fast
//            }
            Task.detached {
                do {
                    // Perform the text-recognition request.
                    try requestHandler.perform([request])
                } catch {
                    log.warning("Unable to perform the vision requests: \(error).")
                }
            }
        } catch {
            log.warning("Failed to generate thumbnail! \(error)")
        }
    }
    
    func recognizeTextHandler(request: VNRequest, error: Error?) {
        highlight.removeAll()
        let recognizedStringsAndRects = procVisionResult(request: request, error: error, minConfidence: 0.0)
        recognizedStringsAndRects.forEach { data in
            if data.0.lowercased().contains((filter.lowercased())) {
                highlight.append(data.1)
            }
        }
    }
    
    func updateSelection() {
        selection = selection + 1
        if selection >= highlight.count {
            selection = 0
        }
    }
    
    func offsetForEpisode(episode: Episode) -> Double {
        var offset_sum = 0.0
        let active_interval: AppInterval? = episodeModel.appIntervals.first { interval in
            offset_sum = offset_sum + (interval.episode.end!.timeIntervalSinceReferenceDate - interval.episode.start!.timeIntervalSinceReferenceDate)
            return episode.start == interval.episode.start!
        }
        return offset_sum + (active_interval?.length ?? 0.0)
    }
    
    var playerView: some View {
        VStack {
            ZStack {
                if thumbnail != nil {
                    Image(thumbnail!, scale: 1.0, label: Text(""))
                        .resizable()
                        .frame(width: 360, height: 203)
                } else {
                    Spacer().frame(width: 360, height: 203)
                }
                
                GeometryReader { metrics in
                    if highlight.count > selection {
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .cutout(
                                [RoundedRectangle(cornerRadius: 4)
                                    .scale(x: highlight[selection].width * 1.2, y: highlight[selection].height * 1.2)
                                    .offset(x:-180 + (highlight[selection].midX * 360), y:102 - (highlight[selection].midY * 203))]
                            )
                    } else {
                        Color.black
                            .opacity(0.5)
                    }
                }
                
            }
            .padding(0)
            HStack {
                VStack {
                    Text((episode.title ?? "")!.split(separator: " ").dropLast(6).joined(separator: " "))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fontWeight(selected ? .bold : .regular)
                        .lineLimit(1)
                    Text((result.from ).formatted(date: .abbreviated, time: .standard) )
                        .font(SwiftUI.Font.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    if highlight.count > 1 {
                        Group {
                            Button(action: { updateSelection() }) {}
                                .keyboardShortcut(.space, modifiers: [])
                        }.frame(maxWidth: 0, maxHeight: 0).opacity(0)
                        HStack {
                            Text("\(selection+1)/\(highlight.count)")
                            Image(systemName: "arrow.forward")
                                .onTapGesture {
                                    updateSelection()
                                }
                                .opacity(isHoveringNext ? 0.8 : 1.0)
                                .onHover(perform: { hovering in
                                    self.isHoveringNext = hovering
                                    if hovering {
                                        NSCursor.pointingHand.set()
                                    } else {
                                        NSCursor.arrow.set()
                                    }
                                })
                        }
                        .foregroundColor(Color(red: 120.0 / 255.0, green: 120.0 / 255.0, blue: 120.0 / 255.0))
                        .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .foregroundColor(Color(red: 210.0 / 255.0, green: 210.0 / 255.0, blue: 210.0 / 255.0))
                        )
                    }
                    NavigationLink(value: result) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.plain)
                    .opacity(isHoveringExpand ? 0.8 : 1.0)
                    .onHover(perform: { hovering in
                        self.isHoveringExpand = hovering
                        if hovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    })

                    Image(systemName: episode.save ? "star.fill" : "star")
                        .onTapGesture {
                            episode.save = !episode.save
                            do {
                                try viewContext.save()
                            } catch {
                            }
                        }
                        .opacity(isHoveringSave ? 0.8 : 1.0)
                        .onHover(perform: { hovering in
                            self.isHoveringSave = hovering
                            if hovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        })
                    Image(nsImage: bundleCache.getIcon(bundleID: (episode.bundle ?? Bundle.main.bundleIdentifier)!))
                        .frame(width: 32, height: 32)
                }
                .padding(EdgeInsets(top: 10.0, leading: 0.0, bottom: 10.0, trailing: 0.0))
            }
        }
        .frame(width: 360, height: 260)
        .onAppear {
            if genTask == nil {
                genTask = Task {
                    await generateThumbnail(offset: ((result.from.timeIntervalSinceReferenceDate) - (episode.start ?? Date()).timeIntervalSinceReferenceDate))
                }
            }
        }
        .onDisappear {
            genTask?.cancel()
        }
    }


    var body: some View {
        playerView
            .accessibilityLabel("A single recording, with a video player, title, date/time and application context details.")
    }
}
