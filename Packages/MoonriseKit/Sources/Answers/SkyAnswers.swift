import Foundation
import Library
import SkyEngine

/// The Moon's phase now and its next quarter.
public struct MoonAnswer: Sendable {
    public var phaseName: String
    /// Fraction of the disc lit, 0...1.
    public var illumination: Double
    public var waxing: Bool
    public var nextQuarter: SkyEngine.MoonQuarter
    public var nextQuarterDate: Date
    public var rows: [AnswerRow]
    public var spoken: String

    public static func quarterName(_ q: SkyEngine.MoonQuarter) -> String {
        switch q {
        case .new: "New moon"
        case .firstQuarter: "First quarter"
        case .full: "Full moon"
        case .lastQuarter: "Last quarter"
        }
    }

    public init(at date: Date, locale: Locale = .current, timeZone: TimeZone = .current) throws {
        let say = Phrasing(locale: locale, timeZone: timeZone)
        let angle = try SkyEngine.moonPhase(at: date)
        phaseName = DailySummary.phaseName(angle)
        illumination = try SkyEngine.illumination(.moon, at: date).phaseFraction
        waxing = angle < 180
        (nextQuarter, nextQuarterDate) = try SkyEngine.nextMoonQuarter(after: date)
        let lit = "\(Int((illumination * 100).rounded()))%"
        let quarter = Self.quarterName(nextQuarter)
        rows = [
            AnswerRow("Phase", phaseName),
            AnswerRow("Illuminated", lit),
            AnswerRow(quarter, say.short(nextQuarterDate, from: date)),
        ]
        spoken = "\(phaseName), \(lit) lit. \(quarter) \(say.when(nextQuarterDate, from: date))."
    }
}

/// Naked-eye planets well placed tonight, with sunset and sunrise.
public struct TonightAnswer: Sendable {
    public struct Planet: Sendable, Hashable {
        public var name: String
        /// "up now, 32° SE", "rises 21:10" or "highest 22:40, 41°".
        public var detail: String
    }

    public var planets: [Planet]
    public var sunset: Date?
    public var sunrise: Date?
    public var heading: String
    public var rows: [AnswerRow]
    public var spoken: String

    public init(at date: Date, place: Place, locale: Locale = .current, timeZone: TimeZone = .current) throws {
        let say = Phrasing(locale: locale, timeZone: timeZone)
        let t = try Tonight(at: date, from: place.observer)
        sunset = t.sunset
        sunrise = t.sunrise
        heading = "Tonight · \(place.label)"

        let placed = t.planets.filter { $0.best != nil }
        planets = placed.map { p in
            let detail: String
            if p.now.altitude > 0 {
                detail = "up now, \(Int(p.now.altitude.rounded()))° \(Compass.point(p.now.azimuth))"
            } else if let rise = p.rise, rise < t.end {
                detail = "rises \(say.time(rise))"
            } else {
                detail = "highest \(say.time(p.best!.date)), \(Int(p.best!.position.altitude.rounded()))°"
            }
            return Planet(name: p.body.rawValue.capitalized, detail: detail)
        }

        var sun: [String] = []
        if let s = t.sunset { sun.append("sets \(say.time(s))") }
        if let r = t.sunrise { sun.append("rises \(say.time(r))") }
        rows = (planets.isEmpty ? [AnswerRow("Planets", "none well placed")] : planets.prefix(3).map { AnswerRow($0.name, $0.detail) })
            + [AnswerRow("Sun", sun.joined(separator: " · "))]

        var lines: [String] = []
        if let first = placed.first {
            let name = first.body.rawValue.capitalized
            lines.append("Up tonight: \(say.list(planets.map(\.name))).")
            if first.now.altitude > 0 {
                lines.append("\(name) is up now, \(Int(first.now.altitude.rounded()))° in the \(Compass.name(first.now.azimuth)).")
            } else if let rise = first.rise, rise < t.end {
                lines.append("\(name) rises \(say.when(rise, from: date)).")
            } else if let best = first.best {
                lines.append("\(name) is highest \(say.when(best.date, from: date)), \(Int(best.position.altitude.rounded()))° up.")
            }
        } else {
            lines.append("No bright planets are well placed tonight.")
        }
        if let s = t.sunset {
            lines.append("Sunset \(say.time(s)).")
        } else if let r = t.sunrise {
            lines.append("Sunrise \(say.time(r)).")
        }
        spoken = lines.sentences(place.note)
    }
}

/// The three satellites the app features, by NORAD catalogue number.
public enum Satellite: Int, CaseIterable, Sendable {
    case iss = 25544, tiangong = 48274, hubble = 20580

    public var name: String {
        switch self {
        case .iss: "ISS"
        case .tiangong: "Tiangong"
        case .hubble: "Hubble"
        }
    }

    var subject: String { self == .iss ? "The ISS" : name }
}

/// The next pass of one satellite, preferring one that can be seen.
public struct PassAnswer: Sendable {
    public var satellite: Satellite
    public var pass: SatellitePass?
    public var rows: [AnswerRow]
    public var spoken: String

    /// `passes` are this satellite's, in time order, as `SkyEngine.passes` returns them for the next three days.
    public init(satellite: Satellite, passes: [SatellitePass], at date: Date, place: Place, locale: Locale = .current, timeZone: TimeZone = .current) {
        let say = Phrasing(locale: locale, timeZone: timeZone)
        self.satellite = satellite
        let upcoming = passes.filter { $0.set > date }
        let visible = upcoming.first(where: \.visible)
        pass = visible ?? upcoming.first
        guard let p = pass else {
            rows = [AnswerRow("Next pass", "none above 10° in 3 days")]
            spoken = "No \(satellite.name) passes above 10° in the next three days."
            return
        }
        let alt = "\(Int(p.maxAltitude.rounded()))°"
        rows = [
            AnswerRow("Rises", "\(say.short(p.rise, from: date)) \(Compass.point(p.riseAzimuth))", alert: p.rise.timeIntervalSince(date) < 15 * 60),
            AnswerRow("Highest", "\(say.time(p.peak)), \(alt)"),
            AnswerRow("Sets", "\(say.time(p.set)) \(Compass.point(p.setAzimuth))"),
            AnswerRow("Visible", p.visible ? "yes" : "no"),
        ]
        let rise = "rises \(say.when(p.rise, from: date)) in the \(Compass.name(p.riseAzimuth)), \(alt) high."
        if visible != nil {
            spoken = ["\(satellite.subject) \(rise) Visible to the eye."].sentences(place.note)
        } else {
            spoken = ["No visible \(satellite.name) passes in the next three days. The next one \(rise)"].sentences(place.note)
        }
    }
}

extension LibraryPage {
    /// Where the Sky tab can turn to for this page: the Moon, the planets, the 88 constellations and the named stars.
    public var skyTarget: Tour.Target? {
        if let c = link.constellation { return Tour.Target(constellation: c) }
        if let hr = link.hr { return Tour.Target(hr: hr) }
        if let b = link.body, b == Body.moon.rawValue || Body.planets.contains(where: { $0.rawValue == b }) { return Tour.Target(body: b) }
        return nil
    }
}
