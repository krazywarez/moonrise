import CAstronomy
import Foundation

extension SkyEngine {
    /// Moon illumination from which moonlight is taken to hide faint satellites and stars.
    public static let moonlightLimit = 0.25

    /// Next time within `limitDays` after `date` that the body's centre crosses `altitude` degrees going up
    /// (`rising`) or down, without refraction (the convention for twilight); nil if it does not.
    public static func searchAltitude(_ body: Body, altitude: Double, rising: Bool, after date: Date, from observer: Observer, limitDays: Double = 1) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        let r = Astronomy_SearchAltitude(body.astro, observer.astro, rising ? DIRECTION_RISE : DIRECTION_SET, time(date), limitDays, altitude)
        return r.status == ASTRO_SUCCESS ? Self.date(r.time) : nil
    }

    /// Astronomical darkness (Sun below −18°) between `start` and `end`, clipped to them; nil if it never gets that dark.
    public static func darkness(from start: Date, to end: Date, observer: Observer) throws -> DateInterval? {
        let days = end.timeIntervalSince(start) / 86_400
        let dusk = try horizontal(.sun, at: start, from: observer).altitude < -18
            ? start
            : searchAltitude(.sun, altitude: -18, rising: false, after: start, from: observer, limitDays: days)
        guard let dusk, dusk < end else { return nil }
        let dawn = searchAltitude(.sun, altitude: -18, rising: true, after: dusk, from: observer, limitDays: days).map { min($0, end) } ?? end
        return DateInterval(start: dusk, end: dawn)
    }

    /// When the Moon is above the horizon between `start` and `end`, clipped to them.
    public static func moonUp(from start: Date, to end: Date, observer: Observer) throws -> [DateInterval] {
        var out: [DateInterval] = []
        var t = start
        while t < end {
            let days = end.timeIntervalSince(t) / 86_400
            let next = riseSet(.moon, after: t, from: observer, limitDays: days)
            if let set = next.set, next.rise.map({ set < $0 }) ?? true {
                out.append(DateInterval(start: t, end: set))
                t = set.addingTimeInterval(60)
            } else if let rise = next.rise {
                let set = riseSet(.moon, after: rise, from: observer, limitDays: end.timeIntervalSince(rise) / 86_400).set ?? end
                out.append(DateInterval(start: rise, end: set))
                t = set.addingTimeInterval(60)
            } else {
                if try horizontal(.moon, at: t, from: observer, refraction: true).altitude > 0 { out.append(DateInterval(start: t, end: end)) }
                break
            }
        }
        return out
    }

    /// "Dark 20:05–05:42. Moon 62% lit, sets 23:10." The Moon's rise and set are those during darkness,
    /// or during `night` where it never gets fully dark.
    public static func moonAndDarkness(night: DateInterval, dark: DateInterval?, moonUp: [DateInterval], moonIllumination: Double,
                                       time: Date.FormatStyle = .init(date: .omitted, time: .shortened)) -> String {
        let window = dark ?? night
        let up = moonUp.compactMap { $0.intersection(with: window) }.filter { $0.duration > 0 }
        let first = dark.map { "Dark \($0.start.formatted(time))–\($0.end.formatted(time))." } ?? "The sky does not get fully dark."
        let lit = "Moon \(Int((moonIllumination * 100).rounded()))% lit"
        let moon: String
        if up.isEmpty {
            moon = "Moon down throughout."
        } else if up.count == 1, up[0] == window {
            moon = "\(lit), up throughout."
        } else {
            var times: [String] = []
            for i in up {
                if i.start > window.start { times.append("rises \(i.start.formatted(time))") }
                if i.end < window.end { times.append("sets \(i.end.formatted(time))") }
            }
            moon = "\(lit), \(times.joined(separator: ", "))."
        }
        return "\(first) \(moon)"
    }
}
