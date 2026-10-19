import Foundation

/// A reference page. Schema and writing rules: docs/library-content.org.
public struct LibraryPage: Codable, Sendable, Identifiable, Hashable {
    public struct Fact: Codable, Sendable, Hashable {
        public var label: String
        public var value: String
        /// Index into `sources`.
        public var source: Int
    }

    public struct Source: Codable, Sendable, Hashable {
        public var title: String
        public var url: URL
    }

    public struct Image: Codable, Sendable, Hashable {
        public var url: URL
        public var credit: String
        public var licence: String
        /// Page the image is published on.
        public var page: URL
        public var caption: String
    }

    /// Parameters for the page's generated drawing; which fields are set depends on `kind`.
    public struct Drawing: Codable, Sendable, Hashable {
        public var kind: String
        public var radiusKm: Double?
        public var rings: Bool?
        public var axialTiltDeg: Double?
        public var color: String?
        public var spectralType: String?
        public var colorIndex: Double?
        public var type: String?
        public var sizeArcmin: Double?
        public var status: String?
        public var launch: String?
        public var radiusEarth: Double?
        public var orbitAU: Double?
        public var starTempK: Double?
        public var heightM: Double?
        public var diameterM: Double?
    }

    /// What the page describes elsewhere in the app.
    public struct Link: Codable, Sendable, Hashable {
        public var body: String?
        public var constellation: String?
        public var hr: Int?
        public var messier: Int?
        public var spacecraft: String?
    }

    public var id: String
    public var section: LibrarySection
    public var title: String
    public var subtitle: String
    public var facts: [Fact]
    public var essay: String
    public var image: Image?
    public var drawing: Drawing?
    public var link: Link
    public var sources: [Source]

    public var paragraphs: [String] {
        essay.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    public var wordCount: Int {
        essay.split { $0.isWhitespace }.count
    }
}

public enum LibrarySection: String, Codable, Sendable, CaseIterable, Identifiable {
    case sun, planets, dwarfPlanets = "dwarf-planets", moons, constellations, stars, deepSky = "deep-sky", exoplanets, missions, rockets

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sun: "The Sun"
        case .planets: "Planets"
        case .dwarfPlanets: "Dwarf planets"
        case .moons: "Moons"
        case .constellations: "Constellations"
        case .stars: "Stars"
        case .deepSky: "Deep sky"
        case .exoplanets: "Exoplanets"
        case .missions: "Missions"
        case .rockets: "Rockets"
        }
    }
}

public enum Library {
    /// All pages from the bundled `pages/*.json` files, in file order within each section.
    public static let pages: [LibraryPage] = {
        guard let dir = Bundle.module.url(forResource: "pages", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { url -> [LibraryPage] in
                do {
                    return try JSONDecoder().decode([LibraryPage].self, from: Data(contentsOf: url))
                } catch {
                    assertionFailure("\(url.lastPathComponent): \(error)")
                    return []
                }
            }
    }()

    public static func pages(in section: LibrarySection) -> [LibraryPage] {
        pages.filter { $0.section == section }
    }

    public static func page(id: String) -> LibraryPage? {
        pages.first { $0.id == id }
    }

    public static func page(body: String) -> LibraryPage? {
        pages.first { $0.link.body == body }
    }

    public static func page(constellation: String) -> LibraryPage? {
        pages.first { $0.link.constellation == constellation }
    }

    public static func page(spacecraft: String) -> LibraryPage? {
        pages.first { $0.link.spacecraft == spacecraft }
    }

    public static func page(hr: Int) -> LibraryPage? {
        pages.first { $0.link.hr == hr }
    }

    /// Case- and diacritic-insensitive match on title and subtitle first, then facts and essay.
    public static func search(_ query: String) -> [LibraryPage] {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return [] }
        var strong: [LibraryPage] = [], weak: [LibraryPage] = []
        for entry in searchIndex {
            if entry.head.contains(q) || entry.page.id == q { strong.append(entry.page) } else if entry.body.contains(q) { weak.append(entry.page) }
        }
        return strong + weak
    }

    /// Lowercased, diacritic-free text per page, built once: title and subtitle, then essay and facts.
    private static let searchIndex: [(page: LibraryPage, head: String, body: String)] = pages.map { p in
        (p, fold(p.title + "\n" + p.subtitle), fold(p.essay + "\n" + p.facts.map(\.value).joined(separator: "\n")))
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static let relatedLock = NSLock()
    nonisolated(unsafe) private static var relatedCache: [String: [LibraryPage]] = [:]

    /// `page.related()` computed once per page.
    static func cachedRelated(_ page: LibraryPage, compute: () -> [LibraryPage]) -> [LibraryPage] {
        relatedLock.lock()
        if let hit = relatedCache[page.id] { relatedLock.unlock(); return hit }
        relatedLock.unlock()
        let value = compute()
        relatedLock.lock()
        relatedCache[page.id] = value
        relatedLock.unlock()
        return value
    }
}

extension LibraryPage {
    /// Pages named in this page's facts, then in its essay, then pages that mention this one, up to `limit`.
    /// A title also matches by its part before a dash or bracket ("Cassini" for "Cassini–Huygens").
    /// Titles shorter than five characters ("Sun", "Moon", "Io") only count when they are mentioned here.
    public func related(limit: Int = 10) -> [LibraryPage] {
        Library.cachedRelated(self) { uncachedRelated(limit: limit) }
    }

    private func uncachedRelated(limit: Int) -> [LibraryPage] {
        func mentions(_ text: String, _ title: String) -> Bool {
            var search = text.startIndex..<text.endIndex
            while let r = text.range(of: title, range: search) {
                let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
                let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
                if !(before?.isLetter ?? false), !(after?.isLetter ?? false) { return true }
                search = r.upperBound..<text.endIndex
            }
            return false
        }
        func names(_ title: String) -> [String] {
            let short = title.components(separatedBy: CharacterSet(charactersIn: "–(")).first!.trimmingCharacters(in: .whitespaces)
            return short.count >= 5 && short != title ? [title, short] : [title]
        }
        let others = Library.pages.filter { $0.id != id }
        let factText = facts.map(\.value).joined(separator: " ")
        let values = Set(facts.map(\.value))
        let inFacts = others.filter { p in names(p.title).contains { mentions(factText, $0) } }
            .sorted { values.contains($0.title) && !values.contains($1.title) }
        let inEssay = others.filter { p in !inFacts.contains(p) && names(p.title).contains { mentions(essay, $0) } }
        let mentioned = inFacts + inEssay
        let mine = names(title).filter { $0.count >= 5 }
        let mentioning = others.filter { p in !mentioned.contains(p) && mine.contains { mentions(p.essay, $0) } }
        return Array((mentioned + mentioning).prefix(limit))
    }
}
