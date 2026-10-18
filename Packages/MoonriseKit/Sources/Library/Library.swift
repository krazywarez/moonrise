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
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let strong = pages.filter { $0.title.range(of: q, options: opts) != nil || $0.subtitle.range(of: q, options: opts) != nil || $0.id == q.lowercased() }
        let weak = pages.filter { p in
            !strong.contains(p) && (p.essay.range(of: q, options: opts) != nil || p.facts.contains { $0.value.range(of: q, options: opts) != nil })
        }
        return strong + weak
    }
}
