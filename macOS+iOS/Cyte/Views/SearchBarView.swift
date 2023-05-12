//
//  SearchBarView.swift
//  Cyte
//
//  Created by Shaun Narayan on 9/04/23.
//

import Foundation
import SwiftUI
import AVKit

struct SearchBarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var bundleCache: BundleCache
    @EnvironmentObject var episodeModel: EpisodeModel
    
    @StateObject private var agent = Agent.shared
    
    @FocusState private var searchFocused: Bool
    @State private var showUsage = false
    
    @State private var currentExport: AVAssetExportSession?
    
    @State private var progressID = UUID()
    @State private var timer: Timer?
    
    // Hover states
    @State private var isHovering: Bool = false
    @State private var isHoveringSearch: Bool = false
    @State private var isHoveringUsage: Bool = false
    @State private var isHoveringSettings: Bool = false
    @State private var isHoveringFaves: Bool = false
    
    var search: some View {
        VStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                let binding = Binding<String>(get: {
                    self.episodeModel.filter
                }, set: {
                    self.episodeModel.filter = $0
                })
                
#if os(macOS)
                let layout = AnyLayout(HStackLayout())
#else
                let layout = AnyLayout(VStackLayout())
#endif
                layout
                {
                    ZStack(alignment:.trailing) {
                        TextField(
                            "Search \(Agent.shared.isSetup ? "or chat " : "")your history",
                            text: binding
                        )                        
                        .accessibilityLabel("The main search bar for your recordings. Use an FTS formatted search query.")
#if os(macOS)
                        .frame(width: agent.chatLog.count == 0 ? 650 : nil, height: 48)
#else
                        .autocorrectionDisabled(true)
#endif
                        .cornerRadius(5)
                        .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                        .textFieldStyle(.plain)
                        .background(colorScheme == .dark ? .black : .white)
                        .cornerRadius(10.0)
                        .font(Font.title)
                        .foregroundColor(Color(red: 107.0 / 255.0, green: 107.0 / 255.0, blue: 107.0 / 255.0))
                        .focused($searchFocused)
                        .onSubmit {
                            self.episodeModel.runSearch()
                        }
                        Button(action: {
                            self.episodeModel.runSearch()
                        }) {
                            Image(systemName: "paperplane")
#if os(macOS)
                                .onHover(perform: { hovering in
                                    self.isHoveringSearch = hovering
                                    if hovering {
                                        NSCursor.pointingHand.set()
                                    } else {
                                        NSCursor.arrow.set()
                                    }
                                })
#endif
                                .foregroundColor(Color(red: 177.0 / 255.0, green: 181.0 / 255.0, blue: 255.0 / 255.0))
                        }
                        .frame(width: 60, height: 60)
                        .buttonStyle(.plain)
                        .opacity(self.isHoveringSearch ? 0.8 : 1.0)
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10))
                    }
                    .frame(alignment: .leading)
                    
                    HStack {
                        if agent.chatLog.count == 0 {
                            Button(action: {
                                let showing = self.showUsage
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    self.showUsage = !showing
                                }
                                self.episodeModel.refreshData()
                            }) {
                                Image(systemName: showUsage ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            }
                            .accessibilityLabel("Opens the advanced search pane")
                            .padding()
                            .opacity(0.8)
                            .buttonStyle(.plain)
                            .opacity(isHoveringUsage ? 0.8 : 1.0)
#if os(macOS)
                            .onHover(perform: { hovering in
                                self.isHoveringUsage = hovering
                                if hovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            })
#endif
                            Button(action: {
                                episodeModel.highlightedBundle = ""
                                episodeModel.showFaves = !episodeModel.showFaves
                                self.episodeModel.refreshData()
                            }) {
                                Image(systemName: episodeModel.showFaves ? "star.fill": "star")
                            }
                            .accessibilityLabel("Filters results to exclude non-starred")
                            .opacity(0.8)
                            .buttonStyle(.plain)
                            .padding(EdgeInsets(top: 0.0, leading: 0.0, bottom: 0.0, trailing: 0.0))
                            .opacity(isHoveringFaves ? 0.8 : 1.0)
#if os(macOS)
                            .onHover(perform: { hovering in
                                self.isHoveringFaves = hovering
                                if hovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            })
#endif
                            NavigationLink(value: 1) {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("Opens the settings pane")
                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                            .opacity(isHoveringSettings ? 0.8 : 1.0)
                            .buttonStyle(.plain)
#if os(macOS)
                            .onHover(perform: { hovering in
                                self.isHoveringSettings = hovering
                                if hovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            })
#endif
                            Button(action: {
                                episodeModel.resetFilters()
                                self.episodeModel.refreshData()
                            }) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Clears all filters and refreshes the feed")
                            .buttonStyle(.plain)
                            .transformEffect(CGAffineTransformMakeScale(-1, 1))
                            .padding(EdgeInsets(top: 0.0, leading: 25.0, bottom: 0.0, trailing: 0.0))
#if os(macOS)
                            .onHover(perform: { hovering in
                                self.isHovering = hovering
                                if hovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            })
#endif
                            if episodeModel.episodesLengthSum < (60 * 60 * 40) && (currentExport == nil || currentExport!.progress >= 1.0) {
                                Button(action: {
                                    Task {
                                        currentExport = await makeTimelapse(episodes: episodeModel.episodes.reversed())
                                    }
                                }) {
                                    Image(systemName: "timelapse")
                                }
                                .buttonStyle(.plain)
                                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
#if os(macOS)
                                .onHover(perform: { hovering in
                                    self.isHovering = hovering
                                    if hovering {
                                        NSCursor.pointingHand.set()
                                    } else {
                                        NSCursor.arrow.set()
                                    }
                                })
#endif
                            }
                            
                            Spacer()
                            if currentExport != nil && currentExport!.progress < 1.0 {
                                HStack {
                                    ProgressView("Exporting…", value: currentExport!.progress, total: 1.0)
                                        .frame(width: 250)
                                    Button(action: {
                                        currentExport?.cancelExport()
                                        currentExport = nil
                                    }) {
                                        Image(systemName: "stop.circle")
                                    }
                                    .id(progressID)
                                    .onAppear {
                                        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { _ in
                                            progressID = UUID()
                                        })
                                    }
                                    .onDisappear {
                                        timer?.invalidate()
                                    }
                                    .buttonStyle(.plain)
#if os(macOS)
                                    .onHover(perform: { hovering in
                                        self.isHovering = hovering
                                        if hovering {
                                            NSCursor.pointingHand.set()
                                        } else {
                                            NSCursor.arrow.set()
                                        }
                                    })
#endif
                                }
                            }
                        }
                    }
                }
            }
        }
#if os(macOS)
        .padding(EdgeInsets(top: 10, leading: agent.chatLog.count == 0 ? 0 : 210, bottom: 10, trailing: agent.chatLog.count == 0 ? 0 : 210))
#endif
    }
    
    var body: some View {
        search
        if agent.chatLog.count == 0 && self.showUsage {
            AdvancedSearchView()
        }
    }
    
}
