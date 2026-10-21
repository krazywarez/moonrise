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

    /// For each of `dates`, in order: the night's `end` and the planets with a `best` time, brightest first, as
    /// `Tonight(at:from:)` gives them. The 15-minute sampling is shared by dates whose nights end together and start on
    /// the same 15-minute grid: those before the same sunset, and dark dates whole quarter hours apart.
    public static func visiblePlanets(at dates: [Date], from observer: Observer) throws -> [(end: Date, planets: [PlanetTonight])] {
        var night: Night?
        return try dates.map { date in
            // As in `init(at:from:)`.
            let dark = try SkyEngine.horizontal(.sun, at: date, from: observer, refraction: true).altitude < -0.8
            let start = dark ? date : SkyEngine.riseSet(.sun, after: date, from: observer).set ?? date
            let end = SkyEngine.riseSet(.sun, after: start, from: observer).rise ?? start.addingTimeInterval(12 * 3600)
            if night?.covers(start, end) != true { night = try Night(start: start, end: end, from: observer) }
            let n = night!
            let first = Int((start.timeIntervalSince(n.start) / 900).rounded())
            var planets: [PlanetTonight] = []
            for (body, altitudes) in n.altitudes {
                var best: (date: Date, position: Horizontal)?
                for i in first..<n.samples.count where altitudes[i].altitude > 10 && altitudes[i].altitude > best?.position.altitude ?? -90 {
                    best = (n.samples[i], altitudes[i])
                }
                guard best != nil else { continue }
                let rs = SkyEngine.riseSet(body, after: date, from: observer)
                planets.append(PlanetTonight(
                    body: body,
                    magnitude: try SkyEngine.illumination(body, at: date).magnitude,
                    now: try SkyEngine.horizontal(body, at: date, from: observer, refraction: true),
                    best: best,
                    rise: rs.rise,
                    set: rs.set
                ))
            }
            return (end, planets.sorted { $0.magnitude < $1.magnitude })
        }
    }

    /// The planet samples of `Tonight(at:from:)` for a night.
    private struct Night {
        var start: Date
        var end: Date
        var samples: [Date]
        var altitudes: [(Body, [Horizontal])]

        init(start: Date, end: Date, from observer: Observer) throws {
            self.start = start
            self.end = end
            let samples = stride(from: start.timeIntervalSince1970, through: end.timeIntervalSince1970, by: 900).map(Date.init(timeIntervalSince1970:))
            self.samples = samples
            altitudes = try [Body.mercury, .venus, .mars, .jupiter, .saturn].map { body in
                (body, try samples.map { try SkyEngine.horizontal(body, at: $0, from: observer, refraction: true) })
            }
        }

        /// Whether the samples of a night from `start` to `end` are a run of these: the same end, and `start` on or
        /// after this start on its 15-minute grid. Rise and set searches from different dates agree to well under 1 s.
        func covers(_ start: Date, _ end: Date) -> Bool {
            let steps = start.timeIntervalSince(self.start) / 900
            return abs(end.timeIntervalSince(self.end)) < 1 && steps > -0.5 && abs(steps - steps.rounded()) < 0.001
        }
    }
}
