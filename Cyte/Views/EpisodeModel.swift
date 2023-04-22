//
//  EpisodeModel.swift
//  Cyte
//
//  Created by Shaun Narayan on 9/04/23.
//

import Foundation
import SwiftUI

struct AppInterval :Identifiable {
    let episode: CyteEpisode
    var offset: Double = 0.0
    var length: Double = 0.0
    var id: Int { episode.hashValue }
}

class EpisodeModel: ObservableObject {
    @Published var dataID = UUID()
    @Published var episodes: [CyteEpisode] = []
    @Published var intervals: [CyteInterval] = []
    @Published var documentsForBundle: [CyteDocument] = []
    @Published var episodesLengthSum: Double = 0.0
    
    // The search terms currently active
    @Published var filter = ""
    @Published var highlightedBundle = ""
    @Published var showFaves = false
    
    @Published var startDate = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .day, value: -30, to: Date())!
    @Published var endDate = Date()
    
    @Published var appIntervals : [AppInterval] = []
    private var refreshTask: Task<(), Never>? = nil
    
    ///
    /// Set length and offset values on each of the supplied intervals
    ///
    func updateIntervals() {
        var offset = 0.0
        for i in 0..<appIntervals.count {
            appIntervals[i].length = (appIntervals[i].episode.end.timeIntervalSinceReferenceDate - appIntervals[i].episode.start.timeIntervalSinceReferenceDate)
            appIntervals[i].offset = offset
            offset += appIntervals[i].length
        }
    }
    
    func activeInterval(at: Double) -> (AppInterval?, Double) {
        var offset_sum = 0.0
        let active_interval: AppInterval? = appIntervals.first { interval in
            let window_center = at
            let next_offset = offset_sum + (interval.episode.end.timeIntervalSinceReferenceDate - interval.episode.start.timeIntervalSinceReferenceDate)
            let is_within = offset_sum <= window_center && next_offset >= window_center
            offset_sum = next_offset
            return is_within
        }
        return (active_interval, offset_sum)
    }
    
    func refreshData() {
        if refreshTask != nil && !refreshTask!.isCancelled {
            refreshTask!.cancel()
        }
        if refreshTask == nil || refreshTask!.isCancelled {
            refreshTask = Task {
                // debounce to 10ms
                do {
                    try await Task.sleep(nanoseconds: 10_000_000)
                    await performRefreshData()
                } catch { }
            }
        }
    }
    
    ///
    /// Runs queries according to updated UI selections
    /// This is only because I'm not familiar with how Inverse relations work in CoreData,
    /// otherwise FetchRequest would automatically update the view. Please update if you can
    ///
    @MainActor func performRefreshData() {
        dataID = UUID()
        episodes.removeAll()
        intervals.removeAll()
        var _episodes: [CyteEpisode] = []
        
        if self.filter.count < 3 {
            var pred = String("start >= \(startDate.timeIntervalSinceReferenceDate) AND end <= \(endDate.timeIntervalSinceReferenceDate)")
            if highlightedBundle.count != 0 {
                pred += String(" AND bundle == \"\(highlightedBundle)\"")
            }
            if showFaves {
                pred += String(" AND save == 1")
            }
            do {
                _episodes = try CyteEpisode.list(predicate: pred)
                intervals.removeAll()
            } catch { }
        } else {
            let potentials: [CyteInterval] = Memory.shared.search(term: self.filter)
            withAnimation(.easeInOut(duration: 0.3)) {
                intervals = potentials.filter { (interval: CyteInterval) in
                    if showFaves && interval.episode.save != true {
                        return false
                    }
                    if highlightedBundle.count != 0  && interval.episode.bundle != highlightedBundle {
                        return false
                    }
                    let is_within = interval.episode.start >= startDate && interval.episode.end <= endDate
                    let ep_included: CyteEpisode? = _episodes.first(where: { ep in
                        return ep.start == interval.episode.start
                    })
                    if ep_included == nil && is_within {
                        _episodes.append(interval.episode)
                    }
                    return is_within
                }
                _episodes = _episodes.sorted(by: { el,er in el.start > er.start })
            }
        }
        
        episodesLengthSum = 0.0
        appIntervals = _episodes.enumerated().map { (index, episode: CyteEpisode) in
            episodesLengthSum += (episode.end).timeIntervalSinceReferenceDate - (episode.start).timeIntervalSinceReferenceDate
            return AppInterval(episode: episode)
        }
        updateIntervals()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            episodes = _episodes
        }
        // now that we have episodes, if a bundle is highlighted get the documents too
        // @todo break this out into its own component and use FetchRequest
        documentsForBundle.removeAll()
        if highlightedBundle.count != 0 {
            do {
                let docs = try CyteDocument.list(predicate: "bundle == \"\(highlightedBundle)\"")
                var paths = Set<URL>()
                for doc in docs {
                    if !paths.contains(doc.path) {
                        withAnimation(.easeIn(duration: 0.3)) {
                            documentsForBundle.append(doc)
                        }
                        paths.insert(doc.path)
                    }
                }
            } catch {
                
            }
        }
    }
    
    func resetFilters() {
        filter = ""
        highlightedBundle = ""
        showFaves = false
        
        startDate = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .day, value: -30, to: Date())!
        endDate = Date()
    }
    
    func runSearch() {
        if Agent.shared.isSetup && filter.hasSuffix("?") {
            Task {
                if refreshTask != nil && !refreshTask!.isCancelled {
                    refreshTask!.cancel()
                }
                if !self.filter.hasPrefix("chat ") {
                    Agent.shared.reset()
                }
                let what = self.filter
                self.filter = ""
                await Agent.shared.query(request: what, over: intervals)
            }
        } else {
            refreshData()
        }
    }
}
