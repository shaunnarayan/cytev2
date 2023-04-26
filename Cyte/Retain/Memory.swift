///
///  Memory.swift
///  Cyte
///
///  Created by Shaun Narayan on 3/03/23.
///

import Foundation
import AVKit
import OSLog
import Combine
import SQLite
import NaturalLanguage
import CoreData
import SwiftDiff

/// A structure that contains the video data to render.
struct CapturedFrame {
    static let invalid = CapturedFrame(surface: nil, data: nil, contentRect: .zero, contentScale: 0, scaleFactor: 0)
    
    let surface: IOSurface?
    let data: CVPixelBuffer?
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat
    var size: CGSize { contentRect.size }
}

///
///  Tracks active application context (driven by external caller)
///  Opens, encodes and closes the video stream, triggers analysis on frames
///  and indexes the resultant information for search
///
@MainActor
class Memory {
    static let shared = Memory()
    
    /// Intra-episode/context processing
    private var assetWriter : AVAssetWriter? = nil
    private var assetWriterInput : AVAssetWriterInput? = nil
    private var assetWriterAdaptor : AVAssetWriterInputPixelBufferAdaptor? = nil
    private var frameCount = 0
    private var currentStart: Date = Date()
    private var episode: Episode?
    private var intervalDb: Connection?
    private var intervalTable: VirtualTable = VirtualTable("Interval")
    
    /// Context change tracking/indexing
    private var lastObservation: String = ""
    
    /// Intel fallbacks - due to lack of hardware acelleration for video encoding and frame analysis, tradeoffs must be made
    private var shouldTrackFileChanges: Bool = true
#if os(macOS)
    static let secondsBetweenFrames : Int = utsname.isAppleSilicon ? 2 : 4
#else
    static let secondsBetweenFrames : Int = 2
#endif
    var currentContext : String = "Startup"
    var currentContextIsPrivate: Bool = false
    var currentUrlContext : URL? = nil
    var currentUrlTime : Date? = nil
    private var skipNextNFrames: Int = 0
    // List of migrations:
    // 0 -> 1 = FST4 to FST5
    private static let DB_VERSION: UserVersion = 1
    private let embedding: NLEmbedding? = NLEmbedding.wordEmbedding(for: NLLanguage.english)
    
    ///
    /// Close any in-progress episodes (in case Cyte was not properly shut down)
    /// Set up the aux database for FTS and embeddings
    ///
    init() {
        let unclosedFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
        unclosedFetch.predicate = NSPredicate(format: "start == end")
        do {
            let url: URL = homeDirectory().appendingPathComponent("CyteMemory.sqlite3")
            intervalDb = try Connection(url.path(percentEncoded: false))

            do {
                let config = FTS4Config()
                    .column(IntervalExpression.from, [.unindexed])
                    .column(IntervalExpression.to, [.unindexed])
                    .column(IntervalExpression.episodeStart, [.unindexed])
                    .column(IntervalExpression.document)
                    .languageId("lid")
                    .order(.desc)

                try intervalDb!.run(intervalTable.create(.FTS4(config), ifNotExists: true))
            }
            
            let fetched = try PersistenceController.shared.container.viewContext.fetch(unclosedFetch)
            for unclosed in fetched {
                delete(delete_episode: unclosed)
            }
            
            // Run migrations
            migrate()
        } catch {
            
        }
    }
    
    func migrate() {
        if intervalDb!.userVersion == 0 {
            log.info("Migrating 0 -> 1")
            var intervals: [CyteInterval] = []
            do {
                // Moving from fts4 to fts5
                // Read intervals into mem, drop the table.
                let stmt = try intervalDb!.prepare("SELECT * FROM Interval")
                while let interval = try stmt.failableNext() {
                    let epStart: Date = Date(timeIntervalSinceReferenceDate: interval[2] as! Double)
                    
                    let epFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
                    epFetch.predicate = NSPredicate(format: "start == %@", epStart as CVarArg)
                    var ep: Episode? = nil
                    do {
                        let fetched = try PersistenceController.shared.container.viewContext.fetch(epFetch)
                        if fetched.count > 0 {
                            ep = fetched.first!
                        }
                        
                    } catch { }
                    
                    if ep != nil {
                        let inter = CyteInterval(from: Date(timeIntervalSinceReferenceDate:interval[0] as! Double), to: Date(timeIntervalSinceReferenceDate:interval[1] as! Double), episode: ep!, document: interval[3] as! String)
                        intervals.append(inter)
                    }
                }
                
                try intervalDb!.run(intervalTable.drop())
                // Create with new FTS config
                do {
                    let config = FTS5Config()
                        .column(IntervalExpression.from, [.unindexed])
                        .column(IntervalExpression.to, [.unindexed])
                        .column(IntervalExpression.episodeStart, [.unindexed])
                        .column(IntervalExpression.document)
                        .tokenizer(Tokenizer.Porter) // @todo remove this for non-english languages
                    
                    try intervalDb!.run(intervalTable.create(.FTS5(config), ifNotExists: true))
                }
                // Insert old data
                for interval in intervals {
                    log.info("Migrate \(interval.from.formatted())")
                    insert(interval: interval)
                }
                
                intervalDb!.userVersion = 1
            } catch {
                log.error("Migration 0 -> 1 Failed")
            }
        }
    }
#if os(macOS)
    ///
    /// Enumerates target directories and filters by last edit time.
    /// This is imperfect for a number of reasons, it is very low granularity for long episodes
    /// it is extremely processor intensive and slow
    ///
    /// Don't think Apple allows file change tracking via callback at such a detailed level,
    /// however surely there is some way to make use of Spotlight cache info on recently edited files
    /// which is a tab in Finder to avoid enumeration?
    ///
    static func getRecentFiles(earliest: Date, latest: Date) -> [(URL, Date)]? {
        let fileManager = FileManager.default
        let homeUrl = fileManager.homeDirectoryForCurrentUser
        
        var recentFiles: [(URL, Date)] = []
        let properties = [URLResourceKey.contentModificationDateKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        
        guard let directoryEnumerator = fileManager.enumerator(at: homeUrl, includingPropertiesForKeys: properties, options: options, errorHandler: nil) else {
            return nil
        }
        
        for case let fileURL as URL in directoryEnumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(properties))
                if let modificationDate = resourceValues.contentModificationDate {
                    if !fileURL.hasDirectoryPath &&
                        (modificationDate >= earliest) &&
                        (modificationDate <= latest) {
                        recentFiles.append((fileURL, modificationDate))
                    }
                }
            } catch {
                log.error("Error reading attributes for file at \(fileURL.path): \(error.localizedDescription)")
            }
        }
        
        recentFiles.sort(by: { $0.1 > $1.1 })
        return recentFiles
    }

    ///
    /// Wraps the provided context and updates with browser awareness
    ///
    func browserAwareContext(front: NSRunningApplication, window_title: String) -> CyteAppContext {
        var title = window_title
        var context = front.bundleIdentifier ?? ""
        
        var url: URL? = nil
        if context.count > 0 {
            let url_and_title = getAddressBarContent(context: context)
            if url_and_title.1 != nil {
                url = URL(string: url_and_title.1!)
                if url != nil {
                    context = url!.host ?? context
                } else {
                    log.error("Failed to parse url \(url_and_title.1!)")
                }
            }
            if url_and_title.0 != nil {
                title = url_and_title.0!
            }
        } else {
            context = "Unnamed"
        }
        if currentUrlContext != nil && url != currentUrlContext && episode != nil {
            // create document
            let doc = Document(context: PersistenceController.shared.container.viewContext)
            doc.path = currentUrlContext
            doc.episode = episode
            doc.start = currentUrlTime
            doc.end = Date()
            do {
                try PersistenceController.shared.container.viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
        if currentUrlContext != url {
            // only update the url time when it changes
            currentUrlTime = Date()
        }
        currentUrlContext = url
        
        let isPrivate = isPrivateContext(context:context)
        if !isPrivate && currentContextIsPrivate {
            skipNextNFrames = 1
        }
        return CyteAppContext(front: front, title: title, context: context, isPrivate: isPrivate)
    }
#endif
    ///
    /// Check the currently active app, if different since last check
    /// then close the current episode and start a new one
    /// Ignores the main bundle (Cyte) - creates sometimes undiscernable
    /// memories with many layers of picture in picture
    ///
    @MainActor
    func updateActiveContext(windowTitles: Dictionary<String, String>, bundleId: String = "") {
#if os(macOS)
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let title: String = windowTitles[front.bundleIdentifier ?? ""] ?? ""
        let ctx = browserAwareContext(front: front, window_title:title)
#else
        let ctx = CyteAppContext(front: iRunningApplication(bundleID: bundleId, isActive: true, localizedName: bundleId), title: bundleId, context: bundleId, isPrivate: false)
#endif
        
        if ctx.front.isActive && (currentContext != ctx.context || currentContextIsPrivate != ctx.isPrivate) {
            if assetWriter != nil && assetWriterInput!.isReadyForMoreMediaData {
                closeEpisode()
            }
            currentContext = ctx.context
            currentContextIsPrivate = ctx.isPrivate
            let exclusion = Memory.shared.getOrCreateBundleExclusion(name: currentContext)
            let is_main_bundle = (currentContext == Bundle.main.bundleIdentifier) || (currentContext == "io.cyte.ios")
            if assetWriter == nil && !is_main_bundle && exclusion.excluded == false && !currentContextIsPrivate {
                var title = ctx.title
                if title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).count == 0 {
                    title = ctx.front.localizedName ?? currentContext
                }
                // hack always skip 1 frame for sync issue between tracking and record
                skipNextNFrames = 1
                openEpisode(title: title)
            } else {
                log.info("Bypass exclusion context \(currentContext)")
            }
        }
    }
    
    ///
    /// Sets up an MPEG4 stream to disk, HD resolution
    ///
    func openEpisode(title: String) {
        log.info("Open \(title)")
        
        currentStart = Date()
        let full_title = "\(String(title.replacingOccurrences(of: "/", with: ".").replacingOccurrences(of: ":", with: ".").prefix(200))) \(currentStart.formatted(date: .abbreviated, time: .standard).replacingOccurrences(of: ":", with: "."))"
        let outputMovieURL = urlForEpisode(start: currentStart, title: full_title)
        do {
            try FileManager.default.createDirectory(at: outputMovieURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        } catch { fatalError("Failed to create dir") }
        //create an assetwriter instance
        do {
            try assetWriter = AVAssetWriter(outputURL: outputMovieURL, fileType: .mov)
        } catch {
            abort()
        }
        //generate 1080p settings
        let settingsAssistant = AVOutputSettingsAssistant(preset: .hevc1920x1080)?.videoSettings
        //create a single video input
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: settingsAssistant)
        //create an adaptor for the pixel buffer
        assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput!, sourcePixelBufferAttributes: nil)
        //add the input to the asset writer
        assetWriter!.add(assetWriterInput!)
        //begin the session
        assetWriter!.startWriting() // Doesn't matter this is on the main thread since the UI isn't open when it's called
        assetWriter!.startSession(atSourceTime: CMTime.zero)
        
        episode = Episode(context: PersistenceController.shared.container.viewContext)
        episode!.start = currentStart
        episode!.bundle = currentContext
        episode!.title = full_title
        episode!.end = currentStart
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
#if os(macOS)
    ///
    /// Saves all files edited within the episodes interval (as per last edit time)
    /// to the index for querying
    ///
    func trackFileChanges(ep: Episode) {
        if shouldTrackFileChanges {
            // Make this follow a user preference, since it chews cpu
            let files = Memory.getRecentFiles(earliest: ep.start!, latest: ep.end!)
            for fileAndModified: (URL, Date) in files! {
                let doc = Document(context: PersistenceController.shared.container.viewContext)
                doc.path = fileAndModified.0
                doc.episode = ep
                doc.start = ep.start
                doc.end = fileAndModified.1
                do {
                    try PersistenceController.shared.container.viewContext.save()
                } catch {
                    let nsError = error as NSError
                    fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                }
                Agent.shared.index(path: doc.path!)
            }
        }
    }
#endif
    ///
    /// Helper function for closeEpisode, clear values
    ///
    private func reset()  {
        self.assetWriterInput = nil
        self.assetWriter = nil
        self.assetWriterAdaptor = nil
        self.frameCount = 0
        self.episode = nil
    }
    
    ///
    /// Save out the current file, create a DB entry and reset streams.
    ///
    func closeEpisode() {
        if assetWriter == nil {
            return
        }
        log.info("Close \(episode?.title ?? "")")
        //close everything
        assetWriterInput!.markAsFinished()
        if frameCount < 1 {
            assetWriter!.cancelWriting()
            delete(delete_episode: episode!)
            log.info("Supressed small episode for \(self.currentContext)")
        } else {
            self.episode!.end = Date()
            let ep = self.episode!
            let frame_count = self.frameCount
            assetWriter!.finishWriting {
                log.info("Finished writing episode")
#if os(macOS)
                if (frame_count * Memory.secondsBetweenFrames) > 30 {
                    log.info("Tracking file changes...")
                    self.trackFileChanges(ep:ep)
                    log.info("Finished tracking")
                }
#endif
            }
            
            do {
                try PersistenceController.shared.container.viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
        self.runRetention()
        self.reset()
    }
    
    ///
    /// Unless the user has specified unlimited retention, calculate a cutoff and
    /// query then delete episodes and all related data
    ///
    private func runRetention() {
        // delete any episodes outside retention period
        let defaults = UserDefaults(suiteName: "group.io.cyte.ios")!
        let retention = defaults.integer(forKey: "CYTE_RETENTION")
        if retention == 0 {
            // retain forever
            log.info("Retain forever")
            return
        }
        let cutoff = Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .day, value: -(retention), to: Date())!
        log.info("Culling memories older than \(cutoff.formatted())")
        let episodeFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
        episodeFetch.predicate = NSPredicate(format: "start < %@", cutoff as CVarArg)
        do {
            let episodes = try PersistenceController.shared.container.viewContext.fetch(episodeFetch)
            for episode in episodes {
                delete(delete_episode: episode)
            }
        } catch {
            log.error("Failed to fetch episodes in retention")
        }
    }
    
    ///
    /// Push frame to encoder, run analysis (which will call us back with results for observation)
    ///
    @MainActor
    func addFrame(frame: CapturedFrame, secondLength: Int64) {
        if skipNextNFrames > 0 {
            skipNextNFrames -= 1
            return
        }
        if assetWriter != nil {
            if assetWriterInput!.isReadyForMoreMediaData {
                let frameTime = CMTimeMake(value: Int64(frameCount) * secondLength, timescale: 1)
                //append the contents of the pixelBuffer at the correct time
                assetWriterAdaptor!.append(frame.data!, withPresentationTime: frameTime)
                Analysis.shared.runOnFrame(frame: frame)
                frameCount += 1
            }
        }
    }

    ///
    ///  Given a string representing visual observations for an instant,
    ///  diff against the last observations and when the change seems
    ///  non-additive, trigger a full text index with optional embedding.
    ///  When additive, save the delta only to save space and simplify search
    ///  duplication resolution
    ///
    @MainActor
    func observe(what: String, at: Date) async {
        var _episode = episode
        if _episode == nil {
            log.info("Found nil episode, recall from DB for straggling observation")
            let episodeFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
            episodeFetch.sortDescriptors = [NSSortDescriptor(key:"start", ascending: false)]
            episodeFetch.fetchLimit = 1
            let episodes = try! PersistenceController.shared.container.viewContext.fetch(episodeFetch)
            _episode = episodes.first
            if( _episode == nil ) {
                // most likely the episode was cleaned up for being too short
                log.warning("Failed to observe \(what) : \(at)")
                return
            }
        }
        let result = cleanupSemantic(diffs: diff(text1: lastObservation, text2: what))
        
        var added: String = ""
        var equal_count = 0
        for res in result {
            switch res {
            case .insert:
                added += res.text
            case .delete:
                break
            case .equal:
                equal_count += 1
                break
            }
        }

        let newItem = CyteInterval(
            from: at,
            to: Calendar(identifier: Calendar.Identifier.iso8601).date(byAdding: .second, value: Memory.secondsBetweenFrames, to: at)!,
            episode: _episode!, document: added)
        insert(interval: newItem)
        lastObservation = what
    }

    ///
    /// Deletes the provided episode including the underlying video file, and indexed interval data
    ///
    func delete(delete_episode: Episode) {
        if delete_episode.save {
            log.info("Saved episode from deletion")
            return
        }
        let docFetch : NSFetchRequest<Document> = Document.fetchRequest()
        docFetch.predicate = NSPredicate(format: "episode == %@", delete_episode)
        if let result = try? PersistenceController.shared.container.viewContext.fetch(docFetch) {
            for object in result {
                PersistenceController.shared.container.viewContext.delete(object)
            }
        }
        let intervals = intervalTable.filter(IntervalExpression.episodeStart == delete_episode.start!.timeIntervalSinceReferenceDate)
        do {
            let url = urlForEpisode(start: delete_episode.start, title: delete_episode.title)
            try FileManager.default.removeItem(at: url)
        } catch {
            log.error(error)
        }
        do {
            try intervalDb!.run(intervals.delete())
        } catch {
            log.error(error)
        }
        PersistenceController.shared.container.viewContext.delete(delete_episode)
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
            log.error(error)
        }
    }
    
    ///
    /// If expanding is non-zero, nouns and verbs in the search query will be replaced with
    /// an FTS query for it and similar words per embedding distance
    ///
    private func expand(term: String, expand_by: Int) -> String {
        var finalTerm = term
        var expanding = 0
        for char in term {
            if char == ">" {
                expanding += 1
            } else {
                break
            }
        }
        finalTerm = String(finalTerm.dropFirst(expanding))
        expanding = expand_by > expanding ? expand_by : expanding
        if expanding > 0 {
            log.info("Expanding by \(expanding)")
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = finalTerm
            let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
            var replacements: [(String, String)] = []
            tagger.enumerateTags(in: finalTerm.startIndex..<finalTerm.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
                if let tag = tag {
                    // if verb or noun
                    if tag.rawValue == "Noun" || tag.rawValue == "Verb" {
                        let concept = String(finalTerm[tokenRange])
                        log.info("Try to expand \(concept)")
                        var replacement = ""
                        embedding!.enumerateNeighbors(for: concept, maximumCount: expanding) { neighbor, distance in
                            log.info("Expand with \(neighbor)")
                            replacement += " OR \(neighbor)"
                            return true
                        }
                        if replacement.count > 0 {
                            replacement = "(\(concept)\(replacement))"
                        } else {
                            replacement = concept
                        }
                        replacements.append((concept, replacement))
                    }
                }
                return true
            }
            for replacement in replacements {
                finalTerm = finalTerm.replacing(replacement.0, with: "\"\(replacement.1)\"")
            }
            finalTerm = "NEAR(\(finalTerm), 100)"
        }
        return finalTerm
    }
    
    ///
    /// Peforms a full text search using FTSv4, with a hard limit of 64 most recent results
    ///
    func search(term: String, expand_by: Int = 0) -> [CyteInterval] {
        var result: [CyteInterval] = []
        do {
            let finalTerm = expand(term: term, expand_by: expand_by)
            
            log.debug(finalTerm)
            let stmt = finalTerm.count > 0 ?
            try intervalDb!.prepare("SELECT *, snippet(Interval, -1, '', '', '', 1) FROM Interval WHERE Interval MATCH '\(finalTerm)' ORDER BY bm25(Interval) LIMIT 64") :
            try intervalDb!.prepare("SELECT *, snippet(Interval, -1, '', '', '', 1) FROM Interval LIMIT 64")
        
            while let interval = try stmt.failableNext() {
                let epStart: Date = Date(timeIntervalSinceReferenceDate: interval[2] as! Double)
                
                let epFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
                epFetch.predicate = NSPredicate(format: "start == %@", epStart as CVarArg)
                var ep: Episode? = nil
                do {
                    let fetched = try PersistenceController.shared.container.viewContext.fetch(epFetch)
                    if fetched.count > 0 {
                        ep = fetched.first!
                    }
                    
                } catch {
                    //failed, fallback to create
                }
                
                if ep != nil {
                    let inter = CyteInterval(from: Date(timeIntervalSinceReferenceDate:interval[0] as! Double), to: Date(timeIntervalSinceReferenceDate:interval[1] as! Double), episode: ep!, document: interval[3] as! String, snippet: interval[4] as? String)
                    result.append(inter)
                } else {
                    log.error("Found an interval without base episode - dangling ref")
                    let inter = intervalTable.filter(IntervalExpression.episodeStart == epStart.timeIntervalSinceReferenceDate)
                    try intervalDb!.run(inter.delete())
                }
            }
        } catch { }
        return result
    }
    
    func insert(interval: CyteInterval) {
        do {
            let _ = try intervalDb!.run(intervalTable.insert(IntervalExpression.from <- interval.from.timeIntervalSinceReferenceDate,
                                                                 IntervalExpression.to <- interval.to.timeIntervalSinceReferenceDate,
                                                                 IntervalExpression.episodeStart <- interval.episode.start!.timeIntervalSinceReferenceDate,
                                                                 IntervalExpression.document <- interval.document
                                                                ))
        } catch {
            fatalError("insertion failed: \(error)")
        }
    }
    
    ///
    /// Returns the BundleExclusion associated with the given bundle name
    /// If unknown, it is created with default values
    ///
    func getOrCreateBundleExclusion(name: String, excluded: Bool = false) -> BundleExclusion {
        let bundleFetch : NSFetchRequest<BundleExclusion> = BundleExclusion.fetchRequest()
        bundleFetch.predicate = NSPredicate(format: "bundle == %@", name)
        do {
            let fetched = try PersistenceController.shared.container.viewContext.fetch(bundleFetch)
            if fetched.count > 0 {
                return fetched.first!
            }
        } catch {
            //failed, fallback to create
        }
        let bundle = BundleExclusion(context: PersistenceController.shared.container.viewContext)
        bundle.bundle = name
        bundle.excluded = excluded
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
        }
        return bundle
    }
}
