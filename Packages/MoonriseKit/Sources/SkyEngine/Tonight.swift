import Foundation

public struct PlanetTonight: Sendable {
    public var body: Body
    public var magnitude: Double
    public var now: Horizontal
    /// Highest point during the night, if it gets above 10°.
    public var best: (date: Date, position: Horizontal)?
    public var rise: Date?
    public var set: Date?
}

public struct Tonight: Sendable {
    /// Darkness window: from now if it is already dark, else from the next sunset.
    public var start: Date
    public var end: Date
    public var sunset: Date?
    public var sunrise: Date?
    /// Astronomical dusk to dawn (Sun below −18°) within start...end; nil where it never gets that dark.
    public var dark: DateInterval?
    /// When the Moon is above the horizon within start...end.
    public var moonUp: [DateInterval]
    public var moonIllumination: Double
    public var moonPhase: Double
    public var nextQuarter: (quarter: SkyEngine.MoonQuarter, date: Date)
    /// Naked-eye planets, those visible tonight first, brightest first.
    public var planets: [PlanetTonight]

    public init(at date: Date, from observer: Observer) throws {
        let sunNow = try SkyEngine.horizontal(.sun, at: date, from: observer, refraction: true)
        let sunToday = SkyEngine.riseSet(.sun, after: date, from: observer)
        if sunNow.altitude < -0.8 {
            start = date
            sunset = nil
        } else {
            sunset = sunToday.set
            start = sunToday.set ?? date
        }
        sunrise = SkyEngine.riseSet(.sun, after: start, from: observer).rise
        end = sunrise ?? start.addingTimeInterval(12 * 3600)
        dark = try SkyEngine.darkness(from: start, to: end, observer: observer)
        moonUp = try SkyEngine.moonUp(from: start, to: end, observer: observer)

        moonIllumination = try SkyEngine.illumination(.moon, at: date).phaseFraction
        moonPhase = try SkyEngine.moonPhase(at: date)
        nextQuarter = try SkyEngine.nextMoonQuarter(after: date)

        let samples = stride(from: start.timeIntervalSince1970, through: end.timeIntervalSince1970, by: 900).map(Date.init(timeIntervalSince1970:))
        planets = try [Body.mercury, .venus, .mars, .jupiter, .saturn].map { body in
            var best: (Date, Horizontal)?
            for s in samples {
                let h = try SkyEngine.horizontal(body, at: s, from: observer, refraction: true)
                if h.altitude > 10, h.altitude > best?.1.altitude ?? -90 { best = (s, h) }
            }
            let rs = SkyEngine.riseSet(body, after: date, from: observer)
            return PlanetTonight(
                body: body,
                magnitude: try SkyEngine.illumination(body, at: date).magnitude,
                now: try SkyEngine.horizontal(body, at: date, from: observer, refraction: true),
                best: best.map { (date: $0.0, position: $0.1) },
                rise: rs.rise,
                set: rs.set
            )
        }
        .sorted { ($0.best != nil ? 0 : 1, $0.magnitude) < ($1.best != nil ? 0 : 1, $1.magnitude) }
    }

    /// Moonrise and moonset during the night, if any.
    public var moonrise: Date? { moonUp.first { $0.start > start }?.start }
    public var moonset: Date? { moonUp.first { $0.end < end }?.end }

    /// Whether the Moon is up during darkness (or the night, where it never gets fully dark) and lit enough to hide faint objects.
    public var moonlit: Bool {
        let window = dark ?? DateInterval(start: start, end: end)
        return moonIllumination >= SkyEngine.moonlightLimit && moonUp.contains { ($0.intersection(with: window)?.duration ?? 0) > 0 }
    }

    /// "Dark 20:05–05:42. Moon 62% lit, sets 23:10."
    public func moonAndDarkness(time: Date.FormatStyle = .init(date: .omitted, time: .shortened)) -> String {
        SkyEngine.moonAndDarkness(night: DateInterval(start: start, end: end), dark: dark, moonUp: moonUp, moonIllumination: moonIllumination, time: time)
    }
}
