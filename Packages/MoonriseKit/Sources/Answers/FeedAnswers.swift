import Feeds
import Foundation
import SkyEngine

/// Kp now and over the next day, and whether aurora may be seen from here.
public struct AuroraAnswer: Sendable {
    public var kpNow: Double
    public var kpNext24h: Double?
    public var observedAt: Date
    /// Kp at which aurora may be seen on the horizon from this place.
    public var kpNeeded: Double
    public var possible: Bool
    public var rows: [AnswerRow]
    public var footnote: String
    public var spoken: String

    static func level(_ kp: Double) -> String {
        if let g = SpaceWeather.gScale(kp) { return "G\(g) storm" }
        return kp < 4 ? "quiet" : "active"
    }

    public init(weather: SpaceWeather, place: Place, locale: Locale = .current, timeZone: TimeZone = .current) {
        let say = Phrasing(locale: locale, timeZone: timeZone)
        kpNow = weather.kpNow
        kpNext24h = weather.kpNext24h
        observedAt = weather.observedAt
        kpNeeded = Geomagnetic.kpNeeded(place.observer)
        possible = max(kpNow, kpNext24h ?? 0) >= kpNeeded
        let horizon = Geomagnetic.latitude(place.observer) < 0 ? "southern" : "northern"

        let gNow = SpaceWeather.gScale(kpNow)
        rows = [
            AnswerRow("Kp now", say.number(kpNow, digits: 1) + (gNow.map { " · G\($0)" } ?? ""), alert: gNow != nil),
            AnswerRow("Next 24 h", kpNext24h.map { "up to \(say.number($0, digits: 1))" } ?? "–", alert: kpNext24h.flatMap(SpaceWeather.gScale) != nil),
            AnswerRow("Aurora", possible ? "possible, \(horizon) horizon" : "unlikely here"),
        ]
        footnote = "NOAA SWPC · \(say.time(observedAt))"

        var lines = ["Kp \(say.number(kpNow, digits: 1)), \(Self.level(kpNow))."]
        if let next = kpNext24h, next > kpNow { lines.append("Up to Kp \(say.number(next, digits: 1)) in the next 24 hours.") }
        if possible {
            lines.append("Aurora possible low on the \(horizon) horizon.")
        } else if kpNeeded > 9 {
            lines.append("Aurora is out of reach this far from the poles.")
        } else {
            lines.append("Aurora unlikely here. You'd need about Kp \(Int(kpNeeded.rounded(.up))).")
        }
        spoken = lines.sentences(place.note)
    }
}

/// The next launch in the backend's schedule that has not yet flown.
public struct LaunchAnswer: Sendable {
    public var launch: Launch?
    public var rows: [AnswerRow]
    public var spoken: String

    /// Launch Library 2 statuses for launches that have left the pad.
    static let flown: Set<String> = ["Success", "Failure", "Partial Failure", "In Flight"]

    public init(launches: [Launch], at date: Date, locale: Locale = .current, timeZone: TimeZone = .current) {
        let say = Phrasing(locale: locale, timeZone: timeZone)
        launch = launches.filter { $0.net > date && !Self.flown.contains($0.status) }.min { $0.net < $1.net }
        guard let l = launch else {
            rows = []
            spoken = "No upcoming launches are scheduled."
            return
        }
        let mission = l.mission ?? l.name.components(separatedBy: " | ").last ?? l.name
        let site = l.location.components(separatedBy: ",").first ?? l.location
        rows = [
            AnswerRow("Rocket", l.rocket),
            AnswerRow("Mission", mission),
            AnswerRow("From", site),
            AnswerRow("Launch", "\(say.short(l.net, from: date)) · \(l.statusName)", alert: l.status == "Hold"),
        ]
        spoken = "\(l.rocket), \(mission), from \(site) in \(say.duration(l.net.timeIntervalSince(date), spoken: true)). Status: \(l.statusName)."
    }
}
