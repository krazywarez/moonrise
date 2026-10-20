import Answers
import AppIntents
import CoreSpotlight
import Library

/// A Library page for Siri, Shortcuts and Spotlight.
struct LibraryPageEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Library Page"
    static let defaultQuery = LibraryPageQuery()

    let page: LibraryPage
    var id: String { page.id }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(page.title)", subtitle: "\(page.subtitle)", image: .init(systemName: page.section.symbol))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let a = defaultAttributeSet
        a.contentDescription = page.paragraphs.first
        a.keywords = [page.section.title] + page.facts.map(\.value)
        return a
    }
}

struct LibraryPageQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [LibraryPageEntity] {
        identifiers.compactMap { Library.page(id: $0).map(LibraryPageEntity.init) }
    }

    func entities(matching string: String) async throws -> [LibraryPageEntity] {
        Library.search(string).prefix(20).map(LibraryPageEntity.init)
    }

    /// The pages the Sky tab can turn to: the Moon, planets, constellations and named stars.
    /// These are also the names Siri listens for in "Look up …" and "Show … in the sky".
    func suggestedEntities() async throws -> [LibraryPageEntity] {
        Library.pages.filter { $0.skyTarget != nil }.map(LibraryPageEntity.init)
    }
}

extension LibrarySection {
    var symbol: String {
        switch self {
        case .sun: "sun.max"
        case .planets: "circle.circle"
        case .dwarfPlanets: "circle.dotted"
        case .moons: "moon"
        case .constellations: "star.circle"
        case .stars: "star"
        case .deepSky: "sparkles"
        case .exoplanets: "globe"
        case .missions: "antenna.radiowaves.left.and.right"
        case .rockets: "airplane.departure"
        }
    }
}

/// Indexes every Library page in Spotlight once per build; pages only change with an app release.
enum SpotlightIndexer {
    static let key = "spotlightIndexedBuild"

    static func indexIfNeeded() async {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard UserDefaults.standard.string(forKey: key) != build else { return }
        let index = CSSearchableIndex(name: "library")
        do {
            try await index.deleteAppEntities(ofType: LibraryPageEntity.self)
            try await index.indexAppEntities(Library.pages.map(LibraryPageEntity.init))
            UserDefaults.standard.set(build, forKey: key)
        } catch {
            log.error("Spotlight indexing failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
