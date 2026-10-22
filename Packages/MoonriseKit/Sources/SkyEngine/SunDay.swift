import CAstronomy
import Foundation

/// The Sun over one local day: rise, set, noon, and the golden and blue hours (the Sun's centre between −4° and +6°,
/// and between −6° and −4°). Times are nil where the Sun does not cross that altitude, as in polar day or night.
public struct SunDay: Sendable {
    public var start: Date
    public var sunrise: Date?
    public var sunset: Date?
    public var noon: Date?
    public var noonAltitude: Double?
    public var morningBlue: DateInterval?
    public var morningGolden: DateInterval?
    public var eveningGolden: DateInterval?
    public var eveningBlue: DateInterval?
    /// Altitude every 10 minutes from `start` for 24 hours.
    public var path: [(date: Date, altitude: Double)]

    public var dayLength: TimeInterval? {
        guard let r = sunrise, let s = sunset, s > r else { return nil }
        return s.timeIntervalSince(r)
    }

    /// `start` is the local midnight the day begins at.
    public init(start: Date, observer: Observer) throws {
        self.start = start
        let rs = SkyEngine.riseSet(.sun, after: start, from: observer, limitDays: 1)
        sunrise = rs.rise
        sunset = rs.set
        func cross(_ alt: Double, rising: Bool, after d: Date) -> Date? {
            SkyEngine.searchAltitude(.sun, altitude: alt, rising: rising, after: d, from: observer, limitDays: 1)
                .flatMap { $0 < start.addingTimeInterval(86_400) ? $0 : nil }
        }
        func span(_ a: Date?, _ b: Date?) -> DateInterval? {
            guard let a, let b, b > a else { return nil }
            return DateInterval(start: a, end: b)
        }
        let m6 = cross(-6, rising: true, after: start), m4 = cross(-4, rising: true, after: start), p6 = cross(6, rising: true, after: start)
        morningBlue = span(m6, m4)
        morningGolden = span(m4, p6)
        let e6 = cross(6, rising: false, after: start), e4 = cross(-4, rising: false, after: start), e6b = cross(-6, rising: false, after: start)
        eveningGolden = span(e6, e4)
        eveningBlue = span(e4, e6b)

        SkyEngine.lock.lock()
        let h = Astronomy_SearchHourAngleEx(BODY_SUN, observer.astro, 0, SkyEngine.time(start), +1)
        SkyEngine.lock.unlock()
        if h.status == ASTRO_SUCCESS, SkyEngine.date(h.time) < start.addingTimeInterval(86_400) {
            noon = SkyEngine.date(h.time)
            noonAltitude = h.hor.altitude
        }
        path = try (0...144).map { i in
            let d = start.addingTimeInterval(Double(i) * 600)
            return (d, try SkyEngine.horizontal(.sun, at: d, from: observer).altitude)
        }
    }
}
