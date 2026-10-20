import Foundation

/// One hour of a weather forecast, from `date` to an hour later. Cover and chance run from 0 to 1.
public struct HourSample: Sendable, Codable, Equatable {
    public var date: Date
    public var cloudLow: Double
    public var cloudMid: Double
    public var cloudHigh: Double
    public var cloudTotal: Double
    public var precipitationChance: Double
    /// Metres.
    public var visibility: Double

    public init(date: Date, cloudLow: Double, cloudMid: Double, cloudHigh: Double, cloudTotal: Double, precipitationChance: Double, visibility: Double) {
        self.date = date
        self.cloudLow = cloudLow
        self.cloudMid = cloudMid
        self.cloudHigh = cloudHigh
        self.cloudTotal = cloudTotal
        self.precipitationChance = precipitationChance
        self.visibility = visibility
    }

    /// Bright targets show through thin high cloud, so only low and mid cloud count for them.
    public func cover(for target: SkyTarget) -> Double {
        target == .bright ? max(cloudLow, cloudMid) : cloudTotal
    }

    var wet: Bool { precipitationChance >= CloudForecast.wetChance || visibility < CloudForecast.fogVisibility }

    func clear(for target: SkyTarget) -> Bool { !wet && cover(for: target) <= CloudForecast.clearCover }
    func cloudy(for target: SkyTarget) -> Bool { wet || cover(for: target) > CloudForecast.cloudyCover }
}

/// Satellites, planets, the Moon and eclipses are bright; meteors and deep-sky objects are faint and need a dark, clear sky.
public enum SkyTarget: Sendable {
    case bright, faint
}

public enum Rating: String, Sendable {
    case go, marginal, no
}

/// What the forecast says about a time or window: a rating where the forecast is good enough for one, and the reason.
public struct Outlook: Sendable, Equatable {
    public var rating: Rating?
    /// "Clear 22:00–04:00", "90% cloud", "Rain or fog likely".
    public var reason: String
}

/// Hourly cloud for one place, as fetched at `fetched`.
public struct CloudForecast: Sendable, Codable, Equatable {
    public var fetched: Date
    public var hours: [HourSample]

    public init(fetched: Date, hours: [HourSample]) {
        self.fetched = fetched
        self.hours = hours
    }

    /// Hour states, at roughly the 2- and 6-okta marks.
    static let clearCover = 0.3
    static let cloudyCover = 0.7
    static let wetChance = 0.5
    static let fogVisibility = 2000.0
    /// Ratings only for times this close to the forecast's issue, and from a forecast no older than `maxAge`.
    static let maxLead: TimeInterval = 72 * 3600
    static let maxAge: TimeInterval = 24 * 3600
    /// Older than this, forecast figures are shown dimmed with the time they are from.
    public static let staleAge: TimeInterval = 6 * 3600

    public func isStale(now: Date) -> Bool { now.timeIntervalSince(fetched) > Self.staleAge }

    public func hour(at date: Date) -> HourSample? {
        hours.first { $0.date <= date && date < $0.date.addingTimeInterval(3600) }
    }

    private func ratable(until end: Date, now: Date) -> Bool {
        now.timeIntervalSince(fetched) <= Self.maxAge && end.timeIntervalSince(fetched) <= Self.maxLead
    }

    /// Cloud at a moment, such as a satellite pass or an eclipse's maximum; nil outside the forecast.
    public func outlook(at date: Date, target: SkyTarget, now: Date) -> Outlook? {
        guard let h = hour(at: date) else { return nil }
        let figure = "\(percent(h.cover(for: target)))% \(target == .bright ? "low and mid cloud" : "cloud")"
        guard ratable(until: date, now: now) else { return Outlook(rating: nil, reason: figure) }
        if h.wet { return Outlook(rating: .no, reason: "Rain or fog likely") }
        return Outlook(rating: h.clear(for: target) ? .go : h.cloudy(for: target) ? .no : .marginal, reason: figure)
    }

    /// Cloud and moonlight through a window such as the dark part of a night; nil unless the forecast covers all of it.
    /// A good hour is clear and, for faint targets, has the Moon down or under `SkyEngine.moonlightLimit` lit.
    /// Go takes two good hours, or half of a window shorter than two; marginal takes one good hour or two clear, moonlit ones.
    public func outlook(over window: DateInterval, target: SkyTarget, moonUp: [DateInterval], moonIllumination: Double, now: Date,
                        time: Date.FormatStyle = .init(date: .omitted, time: .shortened)) -> Outlook? {
        let parts = hours.compactMap { h -> (hour: HourSample, span: DateInterval)? in
            guard let span = DateInterval(start: h.date, duration: 3600).intersection(with: window), span.duration > 0 else { return nil }
            return (h, span)
        }
        guard !parts.isEmpty, parts.reduce(0, { $0 + $1.span.duration }) >= window.duration - 60 else { return nil }

        let covers = parts.map { percent($0.hour.cover(for: target)) }
        let lo = covers.min()!, hi = covers.max()!
        let figure = lo == hi ? "\(lo)% cloud" : "\(lo)–\(hi)% cloud"
        guard ratable(until: window.end, now: now) else { return Outlook(rating: nil, reason: figure) }

        let moonlight = target == .faint && moonIllumination >= SkyEngine.moonlightLimit
        func moonlit(_ span: DateInterval) -> Bool { moonlight && moonUp.contains { ($0.intersection(with: span)?.duration ?? 0) > 0 } }
        let good = parts.filter { $0.hour.clear(for: target) && !moonlit($0.span) }.map(\.span)
        let goodTime = good.reduce(0) { $0 + $1.duration }
        let litTime = parts.filter { $0.hour.clear(for: target) && moonlit($0.span) }.reduce(0) { $0 + $1.span.duration }
        let wetTime = parts.filter { $0.hour.wet }.reduce(0) { $0 + $1.span.duration }
        let cloudTime = window.duration - goodTime - litTime - wetTime

        // The longest run of good hours.
        var runs: [DateInterval] = []
        for g in good {
            if let last = runs.last, last.end == g.start { runs[runs.count - 1] = DateInterval(start: last.start, end: g.end) } else { runs.append(g) }
        }
        let run = runs.max { $0.duration < $1.duration }
        let clearText = run.map { $0 == window ? "Clear throughout" : "Clear \($0.start.formatted(time))–\($0.end.formatted(time))" }

        // What spoiled the rest of the window.
        let otherwise = [(cloudTime, "cloudy"), (litTime, "moonlit"), (wetTime, "rain or fog")].max { $0.0 < $1.0 }!
        if goodTime >= 2 * 3600 || (window.duration < 2 * 3600 && goodTime >= window.duration / 2) {
            return Outlook(rating: .go, reason: clearText!)
        }
        if goodTime >= 3600 {
            return Outlook(rating: .marginal, reason: "\(clearText!), \(otherwise.1) otherwise")
        }
        if litTime >= 2 * 3600 {
            return Outlook(rating: .marginal, reason: "Clear but moonlit")
        }
        if otherwise.0 == wetTime { return Outlook(rating: .no, reason: "Rain or fog likely") }
        if otherwise.0 == litTime { return Outlook(rating: .no, reason: "Too little clear, dark sky") }
        return Outlook(rating: .no, reason: figure)
    }

    private func percent(_ x: Double) -> Int { Int((x * 100).rounded()) }
}

extension SkyEngine {
    /// The forecast for a meteor shower's peak night or an eclipse seen from here; nil for other events or outside the forecast.
    public static func outlook(for event: SkyEvent, forecast: CloudForecast, observer: Observer, now: Date) throws -> Outlook? {
        guard let w = event.window else { return nil }
        switch event.kind {
        case .meteorShower:
            guard forecast.hour(at: w.start) != nil, forecast.hour(at: w.end.addingTimeInterval(-1)) != nil else { return nil }
            let moon = try moonUp(from: w.start, to: w.end, observer: observer)
            let lit = try illumination(.moon, at: w.start + w.duration / 2).phaseFraction
            return forecast.outlook(over: w, target: .faint, moonUp: moon, moonIllumination: lit, now: now)
        case .lunarEclipse, .solarEclipse:
            return forecast.outlook(at: w.start, target: .bright, now: now)
        default:
            return nil
        }
    }
}
