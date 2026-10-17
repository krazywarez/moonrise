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
/// so call it from one thread at a time.
public enum SkyEngine {
    static func time(_ date: Date) -> astro_time_t {
        // Days since J2000 (2000-01-01 12:00 UTC).
        Astronomy_TimeFromDays((date.timeIntervalSince1970 - 946_728_000) / 86_400)
    }

    static func check(_ status: astro_status_t) throws {
        guard status == ASTRO_SUCCESS else { throw SkyEngineError.astronomy(status: Int(status.rawValue)) }
    }

    public static func equatorial(_ body: Body, at date: Date, from observer: Observer) throws -> Equatorial {
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
        var t = time(date)
        let hor = Astronomy_Horizon(&t, observer.astro, rightAscension, declination, refraction ? REFRACTION_NORMAL : REFRACTION_NONE)
        return Horizontal(altitude: hor.altitude, azimuth: hor.azimuth)
    }

    /// Horizontal positions for many fixed objects at once, from J2000 RA and declination in degrees.
    /// Applies precession and nutation; no aberration or refraction.
    public static func horizontal(j2000 coordinates: [(ra: Double, dec: Double)], at date: Date, from observer: Observer) -> [Horizontal] {
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
        let v = Astronomy_HelioVector(body.astro, time(date))
        try check(v.status)
        return SIMD3(v.x, v.y, v.z)
    }

    public static func illumination(_ body: Body, at date: Date) throws -> Illumination {
        let i = Astronomy_Illumination(body.astro, time(date))
        try check(i.status)
        return Illumination(magnitude: i.mag, phaseFraction: i.phase_fraction)
    }

    /// Moon's ecliptic longitude east of the sun in degrees: 0 new, 90 first quarter, 180 full, 270 last quarter.
    public static func moonPhase(at date: Date) throws -> Double {
        let a = Astronomy_MoonPhase(time(date))
        try check(a.status)
        return a.angle
    }
}
