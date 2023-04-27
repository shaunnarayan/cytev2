//
//  EpisodeView.swift
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

struct EpisodeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var bundleCache: BundleCache
    @EnvironmentObject var episodeModel: EpisodeModel
    
    @State var player: AVPlayer
    @ObservedObject var episode: Episode
    
    @State private var isHoveringSave: Bool = false
    @State private var isHoveringExpand: Bool = false
    @State var filter: String
    @State var selected: Bool
    
    var playerView: some View {
        VStack {
            ZStack {
                VideoPlayer(player: player)
                    .padding(0)
#if !os(macOS)
                    .frame(height: 720)
#endif
                
            }
            .padding(0)
            HStack {
                VStack {
                    #if os(macOS)
                    Text((episode.title ?? "")!.split(separator: " ").dropLast(6).joined(separator: " "))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fontWeight(selected ? .bold : .regular)
                        .lineLimit(1)
                    #else
                    Text(bundleCache.getName(bundleID: episode.bundle ?? ""))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fontWeight(selected ? .bold : .regular)
                        .lineLimit(1)
                    #endif
                    Text((episode.start ?? Date()).formatted(date: .abbreviated, time: .standard) )
                        .font(SwiftUI.Font.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    NavigationLink(value: episode) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.plain)
                    .opacity(isHoveringExpand ? 0.8 : 1.0)
#if os(macOS)
                    .onHover(perform: { hovering in
                        self.isHoveringExpand = hovering
                        if hovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    })
#endif
                    Image(systemName: episode.save ? "star.fill" : "star")
                        .onTapGesture {
                            episode.save = !episode.save
                            do {
                                try viewContext.save()
                            } catch {
                            }
                        }
                        .opacity(isHoveringSave ? 0.8 : 1.0)
#if os(macOS)
                        .onHover(perform: { hovering in
                            self.isHoveringSave = hovering
                            if hovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        })
#endif
                    PortableImage(uiImage: bundleCache.getIcon(bundleID: (episode.bundle ?? Bundle.main.bundleIdentifier!)) )
                        .frame(width: 32, height: 32)
                        .id(bundleCache.id)
                }
                .padding(EdgeInsets(top: 10.0, leading: 0.0, bottom: 10.0, trailing: 0.0))
            }
        }
//        .frame(width: 360, height: 260)
    }


    var body: some View {
        playerView
            .accessibilityLabel("A single recording, with a video player, title, date/time and application context details.")
    }
}
