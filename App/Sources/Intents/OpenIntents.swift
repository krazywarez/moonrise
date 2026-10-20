import Answers
import AppIntents
import Library

/// Opens a Library page; used when a page is tapped in Spotlight. Not marked `.system.open`: that schema
/// needs iOS 27, and a second, iOS 27-only OpenIntent for the same entity is rejected at build time.
struct OpenLibraryPageIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Library Page"
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Page")
    var target: LibraryPageEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.libraryPage = target.page
        return .result()
    }
}

/// Turns the Sky tab to an object; pages with no place in the sky (deep sky, missions) open instead.
struct ShowInSkyIntent: AppIntent {
    static let title: LocalizedStringResource = "Show in Sky"
    static let description = IntentDescription("Turns the Sky tab to the Moon, a planet, a constellation or a bright star.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Object", requestValueDialog: "Which object?")
    var target: LibraryPageEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        if let t = target.page.skyTarget {
            Router.shared.tab = "sky"
            Router.shared.skyTarget = t
        } else {
            Router.shared.libraryPage = target.page
        }
        return .result()
    }
}

struct SearchLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Search the Library"
    static let description = IntentDescription("Opens the Library with results for a search.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Search", requestValueDialog: "What would you like to look for?")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.tab = "library"
        Router.shared.libraryQuery = query
        return .result()
    }
}

/// "Search Moonrise for Cassini" in Siri's own words, without a fixed phrase.
@available(iOS 27, *)
@AppIntent(schema: .system.searchInApp)
struct SearchLibrarySchemaIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.tab = "library"
        Router.shared.libraryQuery = criteria.term
        return .result()
    }
}
