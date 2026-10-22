import AppIntents

enum MoonriseTab: String, AppEnum {
    case sky, system, sun, launches, library

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tab"
    static let caseDisplayRepresentations: [MoonriseTab: DisplayRepresentation] = [
        .sky: "Sky", .system: "System", .sun: "Sun", .launches: "News & launches", .library: "Library",
    ]
}

/// Opens a tab. Compiled into the widget extension too, for Control Center; it runs in the app.
struct OpenTabIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Tab"
    static let description = IntentDescription("Opens Moonrise on the Sky, System, Sun, News & launches or Library tab.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Tab", default: .sky)
    var tab: MoonriseTab

    init() {}

    init(tab: MoonriseTab) {
        self.tab = tab
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        Router.shared.tab = tab.rawValue
        #endif
        return .result()
    }
}
