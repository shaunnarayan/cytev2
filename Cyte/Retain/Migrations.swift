//
//  Migrations.swift
//  Cyte
//
//  Created by Shaun Narayan on 21/04/23.
//

import Foundation
import CoreData
import SQLite

///
/// CoreData style wrapper for Intervals so it is observable in the UI
///
class CyteInterval: ObservableObject, Identifiable, Equatable, Hashable {
    static func == (lhs: CyteInterval, rhs: CyteInterval) -> Bool {
        return (lhs.from == rhs.from) && (lhs.to == rhs.to)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    @Published var from: Date
    @Published var to: Date
    @Published var episode: CyteEpisode
    @Published var document: String
    @Published var snippet: String?
    
    init(from: Date, to: Date, episode: CyteEpisode, document: String, snippet: String? = nil) {
        self.from = from
        self.to = to
        self.episode = episode
        self.document = document
        self.snippet = snippet
    }
    
    @MainActor func insert() throws -> Int64 {
        return try Memory.shared.intervalDb!.run(Memory.shared.intervalTable.insert(IntervalExpression.from <- from.timeIntervalSinceReferenceDate,
                                                             IntervalExpression.to <- to.timeIntervalSinceReferenceDate,
                                                             IntervalExpression.episodeStart <- episode.start.timeIntervalSinceReferenceDate,
                                                             IntervalExpression.document <- document
                                                            ))
    }
    
    @MainActor func delete() throws {
        try Memory.shared.intervalDb!.run(Memory.shared.intervalTable.filter(IntervalExpression.from == self.from.timeIntervalSinceReferenceDate).delete())
    }
    
    var id: String { "ci.\(self.from.timeIntervalSinceReferenceDate)" }
}

class OldInterval: ObservableObject, Identifiable, Equatable, Hashable {
    static func == (lhs: OldInterval, rhs: OldInterval) -> Bool {
        return (lhs.from == rhs.from) && (lhs.to == rhs.to)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    @Published var from: Date
    @Published var to: Date
    @Published var episode: Episode
    @Published var document: String
    @Published var snippet: String?
    
    init(from: Date, to: Date, episode: Episode, document: String, snippet: String? = nil) {
        self.from = from
        self.to = to
        self.episode = episode
        self.document = document
        self.snippet = snippet
    }
    
    @MainActor func insert() throws -> Int64 {
        return try Memory.shared.intervalDb!.run(Memory.shared.intervalTable.insert(IntervalExpression.from <- from.timeIntervalSinceReferenceDate,
                                                             IntervalExpression.to <- to.timeIntervalSinceReferenceDate,
                                                             IntervalExpression.episodeStart <- episode.start!.timeIntervalSinceReferenceDate,
                                                             IntervalExpression.document <- document
                                                            ))
    }
    
    var id: String { "ci.\(self.from.timeIntervalSinceReferenceDate)" }
}

class CyteEpisode: ObservableObject, Identifiable, Equatable, Hashable {
    static func == (lhs: CyteEpisode, rhs: CyteEpisode) -> Bool {
        return (lhs.start == rhs.start) && (lhs.end == rhs.end)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    @Published var id: Int64
    @Published var start: Date
    @Published var end: Date
    @Published var title: String
    @Published var bundle: String
    @Published var save: Bool
    
    init(id: Int64, start: Date, end: Date, title: String, bundle: String, save: Bool) {
        self.id = id
        self.start = start
        self.end = end
        self.title = title
        self.bundle = bundle
        self.save = save
    }
    
    @MainActor func update() throws {
        try Memory.shared.intervalDb!.run(Memory.shared.episodeTable.filter(EpisodeExpression.id == self.id).update(EpisodeExpression.start <- start.timeIntervalSinceReferenceDate,
                                                        EpisodeExpression.end <- end.timeIntervalSinceReferenceDate,
                                                        EpisodeExpression.title <- title,
                                                        EpisodeExpression.bundle <- bundle,
                                                        EpisodeExpression.save <- save
                                                            ))
    }
    
    @MainActor func insert() throws -> Int64 {
        let id = try Memory.shared.intervalDb!.run(Memory.shared.episodeTable.insert(EpisodeExpression.start <- start.timeIntervalSinceReferenceDate,
                                                        EpisodeExpression.end <- end.timeIntervalSinceReferenceDate,
                                                        EpisodeExpression.title <- title,
                                                        EpisodeExpression.bundle <- bundle,
                                                        EpisodeExpression.save <- save
                                                            ))
        self.id = id
        return id
    }
    
    @MainActor func delete() throws {
        try Memory.shared.intervalDb!.run(Memory.shared.intervalTable.filter(IntervalExpression.episodeStart == self.start.timeIntervalSinceReferenceDate).delete())
        try Memory.shared.intervalDb!.run(Memory.shared.documentTable.filter(DocumentExpression.episode_id == self.id).delete())
        try Memory.shared.intervalDb!.run(Memory.shared.episodeTable.filter(EpisodeExpression.id == self.id).delete())
    }
    
    static func fetch(db: Connection, table: Table, id: Int64) throws -> CyteEpisode? {
        let stmt = try db.prepare("SELECT * FROM Episode WHERE id = \(id)")
        if let episode = try stmt.failableNext() {
            let id = episode[0] as! Int64
            let start: Date = Date(timeIntervalSinceReferenceDate: episode[1] as! Double)
            let end: Date = Date(timeIntervalSinceReferenceDate: episode[2] as! Double)
            let title: String = episode[3] as! String
            let bundle: String = episode[4] as! String
            let save: Bool = (episode[5] as! Int64) != 0
            return CyteEpisode(id: id, start: start, end: end, title: title, bundle: bundle, save: save)
        }
        return nil
    }
    
    @MainActor static func list(predicate: String? = nil, limit: Int? = nil) throws -> [CyteEpisode] {
        let query = "SELECT * FROM Episode\(predicate != nil ? " WHERE \(predicate!)" : "") ORDER BY start\(limit != nil ? " LIMIT \(limit!)" : "")"
        let stmt = try Memory.shared.intervalDb!.prepare(query)
        var results: [CyteEpisode] = []
        while let episode = try stmt.failableNext() {
            let id = episode[0] as! Int64
            let start: Date = Date(timeIntervalSinceReferenceDate: episode[1] as! Double)
            let end: Date = Date(timeIntervalSinceReferenceDate: episode[2] as! Double)
            let title: String = episode[3] as! String
            let bundle: String = episode[4] as! String
            let save: Bool = (episode[5] as! Int64) != 0
            results.append(CyteEpisode(id: id, start: start, end: end, title: title, bundle: bundle, save: save))
        }
        return results
    }
}

class CyteDomainExclusion: ObservableObject, Identifiable, Equatable, Hashable {
    static func == (lhs: CyteDomainExclusion, rhs: CyteDomainExclusion) -> Bool {
        return (lhs.domain == rhs.domain)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    @Published var domain: URL
    @Published var excluded: Bool
    
    init(domain: URL, excluded: Bool) {
        self.domain = domain
        self.excluded = excluded
    }
    
    @MainActor func update() throws {
        try Memory.shared.intervalDb!.run(Memory.shared.domainExclusionTable.filter(DomainExclusionExpression.domain == self.domain.absoluteString).update(DomainExclusionExpression.domain <- domain.absoluteString,                                                          DomainExclusionExpression.excluded <- excluded
         ))
    }
    
    @MainActor func insert() throws -> Int64 {
        return try Memory.shared.intervalDb!.run(Memory.shared.domainExclusionTable.insert(DomainExclusionExpression.domain <- domain.path(percentEncoded: false),
                                                                DomainExclusionExpression.excluded <- excluded
                                                            ))
    }
    
    @MainActor static func list() throws -> [CyteDomainExclusion] {
        let stmt = try Memory.shared.intervalDb!.prepare("SELECT * FROM DomainExclusion")
        var results: [CyteDomainExclusion] = []
        while let document = try stmt.failableNext() {
            let domain: URL = URL(string: document[1] as! String)!
            let excluded: Bool = (document[2] as! Int64) != 0
            results.append(CyteDomainExclusion(domain: domain, excluded: excluded))
        }
        return results
    }
    
    var id: String { "cde.\(self.domain)" }
}

class CyteBundleExclusion: ObservableObject, Identifiable, Equatable, Hashable {
    static func == (lhs: CyteBundleExclusion, rhs: CyteBundleExclusion) -> Bool {
        return (lhs.bundle == rhs.bundle)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    @Published var bundle: String
    @Published var excluded: Bool
    
    init(bundle: String, excluded: Bool) {
        self.bundle = bundle
        self.excluded = excluded
    }
    
    @MainActor func update() throws {
        try Memory.shared.intervalDb!.run(Memory.shared.bundleExclusionTable.filter(BundleExclusionExpression.bundle == bundle).update(BundleExclusionExpression.bundle <- bundle,                                                          BundleExclusionExpression.excluded <- excluded
         ))
    }
    
    func insert(db: Connection, table: Table) throws -> Int64 {
        return try db.run(table.insert(BundleExclusionExpression.bundle <- bundle,
                                                                BundleExclusionExpression.excluded <- excluded
                                                            ))
    }
    
    @MainActor static func list(predicate: String? = nil) throws -> [CyteBundleExclusion] {
        let stmt = try Memory.shared.intervalDb!.prepare("SELECT * FROM BundleExclusion\(predicate != nil ? " WHERE \(predicate!)" : "")")
        var results: [CyteBundleExclusion] = []
        while let document = try stmt.failableNext() {
            let bundle: String = document[1] as! String
            let excluded: Bool = (document[2] as! Int64) != 0
            results.append(CyteBundleExclusion(bundle: bundle, excluded: excluded))
        }
        return results
    }
    
    var id: String { "cbe.\(self.bundle)" }
}

class CyteDocument: ObservableObject, Identifiable, Equatable, Hashable {
    static func == (lhs: CyteDocument, rhs: CyteDocument) -> Bool {
        return (lhs.start == rhs.start) && (lhs.end == rhs.end)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    @Published var start: Date
    @Published var end: Date
    @Published var episode: CyteEpisode
    @Published var path: URL
    
    init(start: Date, end: Date, episode: CyteEpisode, path: URL) {
        self.start = start
        self.end = end
        self.episode = episode
        self.path = path
    }
    
    @MainActor func insert() throws -> Int64 {
        print(path)
        print(episode)
        return try Memory.shared.intervalDb!.run(Memory.shared.documentTable.insert(DocumentExpression.start <- start.timeIntervalSinceReferenceDate,
                                       DocumentExpression.end <- end.timeIntervalSinceReferenceDate,
                                       DocumentExpression.path <- path.path(percentEncoded: false),
                                       DocumentExpression.episode_id <- episode.id
                                                            ))
    }
    
    @MainActor static func list(predicate: String? = nil, limit: Int? = nil) throws -> [CyteDocument] {
        let query = "SELECT * FROM Document\(predicate != nil ? " WHERE \(predicate!)" : "")\(limit != nil ? " LIMIT \(limit!)" : "")"
        let stmt = try Memory.shared.intervalDb!.prepare(query)
        var results: [CyteDocument] = []
        while let document = try stmt.failableNext() {
            let start: Date = Date(timeIntervalSinceReferenceDate: document[1] as! Double)
            let end: Date = Date(timeIntervalSinceReferenceDate: document[2] as! Double)
            let path: URL = URL(string: document[3] as! String)!
            let episode_id: Int64 = document[4] as! Int64
            let ep = try! CyteEpisode.fetch(db: Memory.shared.intervalDb!, table: Memory.shared.episodeTable, id: episode_id)!
            results.append(CyteDocument(start: start, end: end, episode: ep, path: path))
        }
        return results
    }
    
    var id: String { "cdoc.\(self.start.timeIntervalSinceReferenceDate)" }
}

///
/// Helper struct for accessing Interval fields from result sets
///
struct IntervalExpression {
    public static let id = Expression<Int64>("id")
    public static let from = Expression<Double>("from")
    public static let to = Expression<Double>("to")
    public static let episodeStart = Expression<Double>("episode_start")
    public static let document = Expression<String>("document")
    public static let snippet = Expression<String>(literal: "snippet(Interval, -1, '', '', '', 5)")
}

struct EpisodeExpression {
    public static let id = Expression<Int64>("id")
    public static let start = Expression<Double>("start")
    public static let end = Expression<Double>("end")
    public static let title = Expression<String>("title")
    public static let bundle = Expression<String>("bundle")
    public static let save = Expression<Bool>("save")
}

struct DocumentExpression {
    public static let id = Expression<Int64>("id")
    public static let start = Expression<Double>("start")
    public static let end = Expression<Double>("end")
    public static let path = Expression<String>("path")
    public static let episode_id = Expression<Int64>("episode_id")
}

struct BundleExclusionExpression {
    public static let id = Expression<Int64>("id")
    public static let bundle = Expression<String>("bundle")
    public static let excluded = Expression<Bool>("excluded")
}

struct DomainExclusionExpression {
    public static let id = Expression<Int64>("id")
    public static let domain = Expression<String>("domain")
    public static let excluded = Expression<Bool>("excluded")
}

extension Memory {
    internal func migrate() {
        if intervalDb!.userVersion == 0 {
            log.info("Migrating 0 -> 1")
            var intervals: [OldInterval] = []
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
                        let inter = OldInterval(from: Date(timeIntervalSinceReferenceDate:interval[0] as! Double), to: Date(timeIntervalSinceReferenceDate:interval[1] as! Double), episode: ep!, document: interval[3] as! String)
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
                    let _ = try! interval.insert()
                }
                
                intervalDb!.userVersion = 1
            } catch {
                log.error("Migration 0 -> 1 Failed")
            }
        }
        if intervalDb!.userVersion == 1 {
            print("Migrating 1 -> 2")
            // Move all data from coredata to sqlite.swift since it supports encryption
            do {
                // Create tables for Episode, Document, BundleExclusion and DomainExclusion
                try! intervalDb!.run(episodeTable.create { t in
                    t.column(EpisodeExpression.id, primaryKey: .autoincrement)
                    t.column(EpisodeExpression.start, unique: true)
                    t.column(EpisodeExpression.end, unique: true)
                    t.column(EpisodeExpression.title)
                    t.column(EpisodeExpression.bundle)
                    t.column(EpisodeExpression.save)
                })
                
                try! intervalDb!.run(documentTable.create { t in
                    t.column(DocumentExpression.id, primaryKey: .autoincrement)
                    t.column(DocumentExpression.start)
                    t.column(DocumentExpression.end)
                    t.column(DocumentExpression.path)
                    t.column(DocumentExpression.episode_id)
                    t.foreignKey(DocumentExpression.episode_id, references: documentTable, DocumentExpression.id)
                })
                
                try! intervalDb!.run(bundleExclusionTable.create { t in
                    t.column(BundleExclusionExpression.id, primaryKey: .autoincrement)
                    t.column(BundleExclusionExpression.bundle)
                    t.column(BundleExclusionExpression.excluded)
                })
                
                try! intervalDb!.run(domainExclusionTable.create { t in
                    t.column(DomainExclusionExpression.id, primaryKey: .autoincrement)
                    t.column(DomainExclusionExpression.domain)
                    t.column(DomainExclusionExpression.excluded)
                })
                
                // migrate episodes before documents
                let episodeFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
                var migratedEpisodes: Dictionary<Date, CyteEpisode> = [:]
                do {
                    let episodes = try PersistenceController.shared.container.viewContext.fetch(episodeFetch)
                    for episode in episodes {
                        let ep = CyteEpisode(id: 0, start: episode.start!, end: episode.end!, title: episode.title!, bundle: episode.bundle!, save: episode.save)
                        let _ = try! ep.insert()
                        log.info("Migrated episode \(ep.title)")
                        migratedEpisodes[ep.start] = ep
                    }
                } catch { }
                
                let documentFetch : NSFetchRequest<Document> = Document.fetchRequest()
                do {
                    let documents = try PersistenceController.shared.container.viewContext.fetch(documentFetch)
                    for document in documents {
                        let ep = migratedEpisodes[document.episode!.start!]!
                        let doc = CyteDocument(start: document.start!, end: document.end!, episode: ep, path: document.path!)
                        if doc.path.absoluteString == "https://" { continue } // Skip malformed docs
                        let _ = try! doc.insert()
                        log.info("Migrated document \(doc.path)")
                    }
                } catch { }
                
                let bundleExclusionFetch : NSFetchRequest<BundleExclusion> = BundleExclusion.fetchRequest()
                do {
                    let exclusions = try PersistenceController.shared.container.viewContext.fetch(bundleExclusionFetch)
                    for exclude in exclusions {
                        let ex = CyteBundleExclusion(bundle: exclude.bundle!, excluded: exclude.excluded)
                        let _ = try ex.insert(db: intervalDb!, table: bundleExclusionTable)
                        log.info("Migrated bundle exclusion \(ex.bundle)")
                    }
                } catch { }
                
                let domainExclusionFetch : NSFetchRequest<DomainExclusion> = DomainExclusion.fetchRequest()
                do {
                    let exclusions = try PersistenceController.shared.container.viewContext.fetch(domainExclusionFetch)
                    for exclude in exclusions {
                        let ex = CyteDomainExclusion(domain: exclude.domain!, excluded: exclude.excluded)
                        let _ = try! ex.insert()
                        log.info("Migrated domain exclusion \(ex.domain)")
                    }
                } catch { }
                // @todo delete the old database
                log.error("Migration 1 -> 2 Complete")
                intervalDb!.userVersion = 2
            }
        }
        let fetched = try! CyteEpisode.list(predicate: "start == end")
        for unclosed in fetched {
            delete(delete_episode: unclosed)
        }
    }
}
