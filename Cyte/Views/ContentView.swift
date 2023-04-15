//
//  ContentView.swift
//  Cyte
//
//  The primary content is a search bar,
//  and a grid of videos with summarised metadata
//
//  Created by Shaun Narayan on 27/02/23.
//

import SwiftUI
import CoreData
import Foundation
import AVKit

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var episodeModel: EpisodeModel
    @StateObject private var agent = Agent.shared
    
    let feedColumnLayoutSmall = [
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50)
    ]
    
    let feedColumnLayout = [
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50)
    ]
    let feedColumnLayoutLarge = [
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50),
        GridItem(.fixed(360), spacing: 50)
    ]

    func offsetForEpisode(episode: Episode) -> Double {
        var offset_sum = 0.0
        let _: AppInterval? = episodeModel.appIntervals.first { interval in
            if interval.episode.start == nil || interval.episode.end == nil { return false }
            offset_sum = offset_sum + (interval.episode.end!.timeIntervalSinceReferenceDate - interval.episode.start!.timeIntervalSinceReferenceDate)
            return episode.start == interval.episode.start
        }
        return offset_sum
    }
    
    var feed: some View {
        GeometryReader { metrics in
            ScrollViewReader { value in
                ScrollView {
                    LazyVGrid(columns: (metrics.size.width > 1500 && utsname.isAppleSilicon) ? feedColumnLayoutLarge : (metrics.size.width > 1200 ? feedColumnLayout : feedColumnLayoutSmall), spacing: 20) {
                        if episodeModel.intervals.count == 0 {
                            ForEach(episodeModel.episodes.filter { ep in
                                return (ep.title ?? "").count > 0 && (ep.start != ep.end)
                            }) { episode in
                                EpisodeView(player: AVPlayer(url: urlForEpisode(start: episode.start, title: episode.title)), episode: episode, filter: episodeModel.filter, selected: false)
                                    .frame(width: 360, height: 260)
                                    .contextMenu {
                                        Button {
                                            Memory.shared.delete(delete_episode: episode)
                                            self.episodeModel.refreshData()
                                        } label: {
                                            Label("Delete", systemImage: "xmark.bin")
                                        }
                                        Button {
                                            revealEpisode(episode: episode)
                                        } label: {
                                            Label("Reveal in Finder", systemImage: "questionmark.folder")
                                        }
                                    }
                                    .id(episode.start)
                            }
                        }
                        else {
                            ForEach(episodeModel.intervals.filter { (interval: CyteInterval) in
                                return (interval.episode.title ?? "").count > 0
                            }) { (interval : CyteInterval) in
                                StaticEpisodeView(asset: AVAsset(url: urlForEpisode(start: interval.episode.start, title: interval.episode.title)), episode: interval.episode, result: interval, filter: interval.snippet ?? episodeModel.filter, selected: false)
                                    .id(interval.from)
                            }
                        }
                    }
                    .accessibilityLabel("A grid of recordings matching current search and filters.")
                    .padding(.all)
                    .animation(.easeInOut(duration: 0.3), value: episodeModel.episodes)
                    .animation(.easeInOut(duration: 0.3), value: episodeModel.intervals)
                }
                .id(self.episodeModel.dataID)
            }
        }
    }
    
    var home: some View {
        Group {
            if agent.chatLog.count > 0 {
                GeometryReader { metrics in
                    ChatView(displaySize: metrics.size)
                }
            }
            SearchBarView()
            
            if agent.chatLog.count == 0 {
                feed
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                home
            }
            .navigationDestination(for: Episode.self) { episode in
                EpisodePlaylistView(player: AVPlayer(url:  urlForEpisode(start: episode.start, title: episode.title)), secondsOffsetFromLastEpisode: offsetForEpisode(episode: episode), filter: episodeModel.filter
                )
            }
            .navigationDestination(for: CyteInterval.self) { interval in
                EpisodePlaylistView(player: AVPlayer(url:  urlForEpisode(start: interval.episode.start, title: interval.episode.title)), secondsOffsetFromLastEpisode: offsetForEpisode(episode: interval.episode) - (interval.from.timeIntervalSinceReferenceDate - interval.episode.start!.timeIntervalSinceReferenceDate), filter: episodeModel.filter
                )
            }
            .navigationDestination(for: Int.self) { path in
                Settings()
            }
        }
        
        .onAppear {
            self.episodeModel.refreshData()
        }
        .padding(EdgeInsets(top: 0.0, leading: 30.0, bottom: 0.0, trailing: 30.0))
        .background(
            Rectangle().foregroundColor(
                colorScheme == .dark ?
                Color(red: 15.0 / 255.0, green: 15.0 / 255.0, blue: 15.0 / 255.0 ) :
                Color(red: 240.0 / 255.0, green: 240.0 / 255.0, blue: 240.0 / 255.0 )
            )
        )
#if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Memory.shared.closeEpisode()
            Task {
                // @todo there are likely some cases in which this shouldn't be updated
                episodeModel.endDate = Date()
                self.episodeModel.refreshData()
            }
        }
#endif
    }
}
