import Foundation
import Library
import SkyEngine
import SkyRenderer

/// The deep-space probes in `Spacecraft.all` that answers cover, by name.
public enum Probe: String, CaseIterable, Sendable {
    case voyager1 = "Voyager 1", voyager2 = "Voyager 2", pioneer10 = "Pioneer 10", pioneer11 = "Pioneer 11", newHorizons = "New Horizons"
}

public enum ProbeAnswerError: Error {
    case noData
}

/// A probe's distance from Earth and the Sun, and the one-way light time.
public struct ProbeAnswer: Sendable {
    public var probe: Probe
    public var fromEarthKm: Double
    public var fromSunAU: Double
    /// Seconds for light to cross `fromEarthKm`.
    public var lightTime: TimeInterval
    public var rows: [AnswerRow]
    public var spoken: String

    public init(probe: Probe, at date: Date, locale: Locale = .current) throws {
        let say = Phrasing(locale: locale, timeZone: .current)
        guard let craft = Spacecraft.all.first(where: { $0.name == probe.rawValue }), let p = craft.position3(at: date) else { throw ProbeAnswerError.noData }
        let d = p - (try SkyEngine.heliocentricEarth(at: date))
        let au = (d * d).sum().squareRoot()
        self.probe = probe
        fromEarthKm = au * 149_597_870.7
        fromSunAU = (p * p).sum().squareRoot()
        lightTime = au * 499.004784
        let billions = "\(say.number(fromEarthKm / 1e9, digits: 1)) billion km"
        rows = [
            AnswerRow("From Earth", billions),
            AnswerRow("From the Sun", "\(say.number(fromSunAU, digits: 1)) AU"),
            AnswerRow("Light time", say.duration(lightTime, spoken: false)),
        ]
        var lines = ["\(probe.rawValue) is \(billions) from Earth. Its signal takes \(say.duration(lightTime, spoken: true)) to reach us."]
        if probe == .pioneer10 || probe == .pioneer11 { lines.append("Contact was lost, so this is a prediction.") }
        spoken = lines.sentences(nil)
    }
}

/// A Library page's subtitle and first three facts.
public struct LookUpAnswer: Sendable {
    public var page: LibraryPage
    public var subtitle: String
    public var rows: [AnswerRow]
    public var spoken: String

    public init(page: LibraryPage) {
        self.page = page
        subtitle = page.subtitle.replacingOccurrences(of: " · ", with: ", ")
        let facts = page.facts.prefix(3)
        rows = facts.map { AnswerRow($0.label, $0.value) }
        spoken = (["\(page.title): \(subtitle)."] + facts.map { "\($0.label): \($0.value)." }).sentences(nil)
    }
}
