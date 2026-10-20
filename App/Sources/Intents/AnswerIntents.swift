import Answers
import AppIntents
import Feeds
import Foundation
import Library
import SkyEngine

extension Place {
    /// The Sky tab's last observer, else the city chosen in Settings, else Chicago.
    static var current: Place {
        let d = UserDefaults.standard
        if let saved = Place.saved(in: d) { return saved }
        if d.string(forKey: SettingsKey.locationMode) == "city", let name = d.string(forKey: SettingsKey.cityName), d.object(forKey: SettingsKey.cityLatitude) != nil {
            return Place(latitude: d.double(forKey: SettingsKey.cityLatitude), longitude: d.double(forKey: SettingsKey.cityLongitude), name: name, kind: .city)
        }
        return .fallback
    }
}

enum AnswerError: Error, CustomLocalizedStringResourceConvertible {
    case offline

    var localizedStringResource: LocalizedStringResource {
        "Moonrise couldn't reach the network. Try again when you're online."
    }
}

/// The whole answer for AirPods and HomePod; its first sentence alongside the result view.
private func dialog(_ spoken: String) -> IntentDialog {
    let first = spoken.components(separatedBy: ". ").first.map { $0.hasSuffix(".") ? $0 : $0 + "." } ?? spoken
    return IntentDialog(full: "\(spoken)", supporting: "\(first)")
}

struct MoonPhaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Moon Phase"
    static let description = IntentDescription("The Moon's phase, how much of it is lit, and the next quarter.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let a = try MoonAnswer(at: .now)
        return .result(dialog: dialog(a.spoken), view: AnswerSnippet(heading: "Moon", rows: a.rows, moon: (a.illumination, a.waxing)))
    }
}

struct TonightIntent: AppIntent {
    static let title: LocalizedStringResource = "Tonight's Sky"
    static let description = IntentDescription("The bright planets well placed tonight, with sunset and sunrise.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let a = try TonightAnswer(at: .now, place: .current)
        return .result(dialog: dialog(a.spoken), view: AnswerSnippet(heading: a.heading, rows: a.rows))
    }
}

enum SatelliteOption: String, AppEnum {
    case iss, tiangong, hubble

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Satellite"
    static let caseDisplayRepresentations: [SatelliteOption: DisplayRepresentation] = [
        .iss: DisplayRepresentation(title: "ISS", synonyms: ["the ISS", "the space station", "the International Space Station"]),
        .tiangong: DisplayRepresentation(title: "Tiangong", synonyms: ["the Chinese space station"]),
        .hubble: DisplayRepresentation(title: "Hubble", synonyms: ["the Hubble Space Telescope", "Hubble telescope"]),
    ]

    var satellite: Satellite {
        switch self {
        case .iss: .iss
        case .tiangong: .tiangong
        case .hubble: .hubble
        }
    }
}

struct NextPassIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Satellite Pass"
    static let description = IntentDescription("When the ISS, Tiangong or Hubble next crosses your sky, preferring a pass you can see.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Satellite", default: .iss)
    var satellite: SatelliteOption

    private struct SatelliteList: Decodable { var satellites: [OrbitalElements] }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let s = satellite.satellite
        guard let apiBase,
              let (data, _) = try? await URLSession.shared.data(from: apiBase.appending(path: "v1/satellites")),
              let list = try? JSONDecoder().decode(SatelliteList.self, from: data) else { throw AnswerError.offline }
        let place = Place.current
        let passes = list.satellites.first { $0.NORAD_CAT_ID == s.rawValue }
            .map { SkyEngine.passes(of: $0, from: .now, hours: 72, observer: place.observer) } ?? []
        let a = PassAnswer(satellite: s, passes: passes, at: .now, place: place)
        return .result(dialog: dialog(a.spoken), view: AnswerSnippet(heading: "\(s.name) · \(place.label)", rows: a.rows))
    }
}

struct NextLaunchIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Launch"
    static let description = IntentDescription("The next rocket launch: rocket, mission, launch site and countdown.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let apiBase, let list = try? await LaunchFeed.fetch(base: apiBase) else { throw AnswerError.offline }
        let a = LaunchAnswer(launches: list.launches, at: .now)
        return .result(dialog: dialog(a.spoken), view: AnswerSnippet(heading: "Next launch", rows: a.rows))
    }
}

struct SpaceWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "Aurora and Kp"
    static let description = IntentDescription("The planetary Kp index now and over the next day, and whether aurora may be seen from your location.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let weather = try? await SpaceWeather.fetch() else { throw AnswerError.offline }
        let place = Place.current
        let a = AuroraAnswer(weather: weather, place: place)
        return .result(dialog: dialog(a.spoken), view: AnswerSnippet(heading: "Space weather · \(place.label)", rows: a.rows, footnote: a.footnote))
    }
}

enum ProbeOption: String, AppEnum {
    case voyager1, voyager2, pioneer10, pioneer11, newHorizons

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Probe"
    static let caseDisplayRepresentations: [ProbeOption: DisplayRepresentation] = [
        .voyager1: DisplayRepresentation(title: "Voyager 1", synonyms: ["Voyager", "Voyager one"]),
        .voyager2: DisplayRepresentation(title: "Voyager 2", synonyms: ["Voyager two"]),
        .pioneer10: DisplayRepresentation(title: "Pioneer 10", synonyms: ["Pioneer ten", "Pioneer"]),
        .pioneer11: DisplayRepresentation(title: "Pioneer 11", synonyms: ["Pioneer eleven"]),
        .newHorizons: DisplayRepresentation(title: "New Horizons"),
    ]

    var probe: Probe {
        switch self {
        case .voyager1: .voyager1
        case .voyager2: .voyager2
        case .pioneer10: .pioneer10
        case .pioneer11: .pioneer11
        case .newHorizons: .newHorizons
        }
    }
}

struct ProbeDistanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Probe Distance"
    static let description = IntentDescription("How far a deep-space probe is from Earth, and how long its signal takes to reach us.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Probe", default: .voyager1)
    var probe: ProbeOption

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let a = try ProbeAnswer(probe: probe.probe, at: .now)
        return .result(dialog: dialog(a.spoken), view: AnswerSnippet(heading: a.probe.rawValue, rows: a.rows))
    }
}

struct LookUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Look Up"
    static let description = IntentDescription("A Library page's description and key facts.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Object", requestValueDialog: "Which object?")
    var page: LibraryPageEntity

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let a = LookUpAnswer(page: page.page)
        return .result(dialog: dialog(a.spoken), view: AnswerSnippet(heading: page.page.title, lead: a.subtitle, rows: a.rows))
    }
}
