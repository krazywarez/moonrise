import CAstronomy
import Foundation

/// A place on Earth. Latitude and longitude in degrees (east positive), height in metres.
public struct Observer: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var height: Double

    public init(latitude: Double, longitude: Double, height: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.height = height
    }

    var astro: astro_observer_t { Astronomy_MakeObserver(latitude, longitude, height) }
}

public enum Body: String, CaseIterable, Sendable {
    case sun, moon, mercury, venus, mars, jupiter, saturn, uranus, neptune, pluto

    public static let planets: [Body] = [.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune]

    var astro: astro_body_t {
        switch self {
        case .sun: BODY_SUN
        case .moon: BODY_MOON
        case .mercury: BODY_MERCURY
        case .venus: BODY_VENUS
        case .mars: BODY_MARS
        case .jupiter: BODY_JUPITER
        case .saturn: BODY_SATURN
        case .uranus: BODY_URANUS
        case .neptune: BODY_NEPTUNE
        case .pluto: BODY_PLUTO
        }
    }
}

/// Apparent right ascension (hours) and declination (degrees) of date, distance in AU.
public struct Equatorial: Sendable, Equatable {
    public var rightAscension: Double
    public var declination: Double
    public var distance: Double
}

/// Altitude above the horizon and azimuth from north through east, both in degrees.
public struct Horizontal: Sendable, Equatable {
    public var altitude: Double
    public var azimuth: Double

    public init(altitude: Double, azimuth: Double) {
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

public struct Illumination: Sendable, Equatable {
    public var magnitude: Double
    /// Fraction of the disc that is lit, 0...1.
    public var phaseFraction: Double
}

public enum SkyEngineError: Error, Equatable {
    case astronomy(status: Int)
}

/// Positions and phases from Astronomy Engine. Its C code keeps internal caches,
/// so every call into it holds one process-wide lock.
public enum SkyEngine {
    static let lock = NSRecursiveLock()

    static func time(_ date: Date) -> astro_time_t {
        // Days since J2000 (2000-01-01 12:00 UTC).
        Astronomy_TimeFromDays((date.timeIntervalSince1970 - 946_728_000) / 86_400)
    }

    static func check(_ status: astro_status_t) throws {
        guard status == ASTRO_SUCCESS else { throw SkyEngineError.astronomy(status: Int(status.rawValue)) }
    }

    public static func equatorial(_ body: Body, at date: Date, from observer: Observer) throws -> Equatorial {
        lock.lock()
        defer { lock.unlock() }
        var t = time(date)
        let eq = Astronomy_Equator(body.astro, &t, observer.astro, EQUATOR_OF_DATE, ABERRATION)
        try check(eq.status)
        return Equatorial(rightAscension: eq.ra, declination: eq.dec, distance: eq.dist)
    }

    public static func horizontal(_ body: Body, at date: Date, from observer: Observer, refraction: Bool = false) throws -> Horizontal {
        let eq = try equatorial(body, at: date, from: observer)
        return horizontal(rightAscension: eq.rightAscension, declination: eq.declination, at: date, from: observer, refraction: refraction)
    }

    /// For fixed objects such as stars: RA in hours, declination in degrees, both of date.
    public static func horizontal(rightAscension: Double, declination: Double, at date: Date, from observer: Observer, refraction: Bool = false) -> Horizontal {
        lock.lock()
        defer { lock.unlock() }
        var t = time(date)
        let hor = Astronomy_Horizon(&t, observer.astro, rightAscension, declination, refraction ? REFRACTION_NORMAL : REFRACTION_NONE)
        return Horizontal(altitude: hor.altitude, azimuth: hor.azimuth)
    }

    /// Horizontal positions for many fixed objects at once, from J2000 RA and declination in degrees.
    /// Applies precession and nutation; no aberration or refraction.
    /// 2000-01-01 12:00 TT.
    public static let j2000 = Date(timeIntervalSince1970: 946_727_935.816)

    /// Right ascension and declination on the equator and equinox of `date` (precession and nutation applied), degrees.
    public static func equatorOfDate(j2000 c: (ra: Double, dec: Double), at date: Date) -> (ra: Double, dec: Double) {
        lock.lock()
        defer { lock.unlock() }
        var t = time(date)
        let rotation = Astronomy_Rotation_EQJ_EQD(&t)
        let ra = c.ra * .pi / 180, dec = c.dec * .pi / 180
        let v = Astronomy_RotateVector(rotation, astro_vector_t(status: ASTRO_SUCCESS, x: cos(dec) * cos(ra), y: cos(dec) * sin(ra), z: sin(dec), t: t))
        var r = atan2(v.y, v.x) * 180 / .pi
        if r < 0 { r += 360 }
        return (r, asin(v.z) * 180 / .pi)
    }

    public static func horizontal(j2000 coordinates: [(ra: Double, dec: Double)], at date: Date, from observer: Observer) -> [Horizontal] {
        lock.lock()
        defer { lock.unlock() }
        var t = time(date)
        let rotation = Astronomy_Rotation_EQJ_HOR(&t, observer.astro)
        return coordinates.map { c in
            let ra = c.ra * .pi / 180, dec = c.dec * .pi / 180
            let v = astro_vector_t(status: ASTRO_SUCCESS, x: cos(dec) * cos(ra), y: cos(dec) * sin(ra), z: sin(dec), t: t)
            let s = Astronomy_HorizonFromVector(Astronomy_RotateVector(rotation, v), REFRACTION_NONE)
            return Horizontal(altitude: s.lat, azimuth: s.lon)
        }
    }

    /// Heliocentric position in AU, J2000 equatorial axes.
    public static func heliocentric(_ body: Body, at date: Date) throws -> SIMD3<Double> {
        lock.lock()
        defer { lock.unlock() }
        let v = Astronomy_HelioVector(body.astro, time(date))
        try check(v.status)
        return SIMD3(v.x, v.y, v.z)
    }

    /// Heliocentric position in AU on J2000 ecliptic axes (x toward the equinox, z toward the ecliptic north pole).
    public static func heliocentricEcliptic(_ body: Body, at date: Date) throws -> SIMD3<Double> {
        ecliptic(try heliocentric(body, at: date))
    }

    /// Earth's heliocentric position in AU on J2000 ecliptic axes.
    public static func heliocentricEarth(at date: Date) throws -> SIMD3<Double> {
        lock.lock()
        defer { lock.unlock() }
        let v = Astronomy_HelioVector(BODY_EARTH, time(date))
        try check(v.status)
        return ecliptic(SIMD3(v.x, v.y, v.z))
    }

    /// J2000 equatorial to J2000 ecliptic axes.
    static func ecliptic(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let e = 23.4392911 * Double.pi / 180
        return SIMD3(v.x, v.y * cos(e) + v.z * sin(e), -v.y * sin(e) + v.z * cos(e))
    }

    public static func illumination(_ body: Body, at date: Date) throws -> Illumination {
        lock.lock()
        defer { lock.unlock() }
        let i = Astronomy_Illumination(body.astro, time(date))
        try check(i.status)
        return Illumination(magnitude: i.mag, phaseFraction: i.phase_fraction)
    }

    static func date(_ t: astro_time_t) -> Date {
        Date(timeIntervalSince1970: 946_728_000 + t.ut * 86_400)
    }

    /// Next rise and next set within `limitDays` after `date`; nil if none in that window.
    public static func riseSet(_ body: Body, after date: Date, from observer: Observer, limitDays: Double = 1) -> (rise: Date?, set: Date?) {
        lock.lock()
        defer { lock.unlock() }
        let t = time(date)
        let rise = Astronomy_SearchRiseSetEx(body.astro, observer.astro, DIRECTION_RISE, t, limitDays, 0)
        let set = Astronomy_SearchRiseSetEx(body.astro, observer.astro, DIRECTION_SET, t, limitDays, 0)
        return (rise.status == ASTRO_SUCCESS ? Self.date(rise.time) : nil,
                set.status == ASTRO_SUCCESS ? Self.date(set.time) : nil)
    }

    public enum MoonQuarter: Int, Sendable {
        case new, firstQuarter, full, lastQuarter
    }

    /// The first lunar quarter after `date`.
    public static func nextMoonQuarter(after date: Date) throws -> (quarter: MoonQuarter, date: Date) {
        lock.lock()
        defer { lock.unlock() }
        let q = Astronomy_SearchMoonQuarter(time(date))
        try check(q.status)
        return (MoonQuarter(rawValue: Int(q.quarter))!, Self.date(q.time))
    }

    /// Moon's ecliptic longitude east of the sun in degrees: 0 new, 90 first quarter, 180 full, 270 last quarter.
    public static func moonPhase(at date: Date) throws -> Double {
        lock.lock()
        defer { lock.unlock() }
        let a = Astronomy_MoonPhase(time(date))
        try check(a.status)
        return a.angle
    }
}
