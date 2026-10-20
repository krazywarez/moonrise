import CAstronomy
import Foundation

/// Ground track of the Moon's umbra (total) or antumbra (annular) for one solar eclipse,
/// from the Sun–Moon shadow axis intersected with the Earth's ellipsoid.
public struct EclipsePath: Sendable {
    public struct Point: Sendable, Equatable {
        public var date: Date
        public var center: (lat: Double, lon: Double)
        public var north: (lat: Double, lon: Double)?
        public var south: (lat: Double, lon: Double)?
        /// Width of the path at this point, km.
        public var widthKm: Double

        public static func == (a: Point, b: Point) -> Bool { a.date == b.date }
    }

    public var kind: String
    public var peak: Date
    /// Greatest eclipse.
    public var greatest: (lat: Double, lon: Double)
    /// Duration of totality or annularity at greatest eclipse, seconds.
    public var centralDuration: TimeInterval?
    public var points: [Point]

    static let sunRadiusKm = 695_700.0
    static let moonRadiusKm = 1_737.4
    static let earthA = 6_378.137
    static let earthF = 1 / 298.257223563
    static let kmPerAU = 1.495978707e8

    /// The path of the first total or annular eclipse whose peak is within a day of `date`.
    public static func compute(near date: Date, step: TimeInterval = 60) -> EclipsePath? {
        SkyEngine.lock.lock()
        defer { SkyEngine.lock.unlock() }
        let g = Astronomy_SearchGlobalSolarEclipse(SkyEngine.time(date.addingTimeInterval(-86_400)))
        guard g.status == ASTRO_SUCCESS, g.kind == ECLIPSE_TOTAL || g.kind == ECLIPSE_ANNULAR else { return nil }
        let peak = SkyEngine.date(g.peak)
        guard abs(peak.timeIntervalSince(date)) < 86_400 else { return nil }

        var points: [Point] = []
        var t = peak.addingTimeInterval(-4 * 3600)
        while t <= peak.addingTimeInterval(4 * 3600) {
            if let p = point(at: t, step: step) { points.append(p) }
            t = t.addingTimeInterval(step)
        }

        let at = Observer(latitude: g.latitude, longitude: g.longitude)
        let local = Astronomy_SearchLocalSolarEclipse(SkyEngine.time(peak.addingTimeInterval(-6 * 3600)), at.astro)
        var duration: TimeInterval?
        if local.status == ASTRO_SUCCESS, local.kind == g.kind {
            duration = SkyEngine.date(local.total_end.time).timeIntervalSince(SkyEngine.date(local.total_begin.time))
        }
        return EclipsePath(kind: SkyEngine.eclipseKind(g.kind), peak: peak, greatest: (g.latitude, g.longitude), centralDuration: duration, points: points)
    }

    /// Centre and limits of the path at `date`, or nil if the shadow axis misses the Earth.
    static func point(at date: Date, step: TimeInterval) -> Point? {
        guard let (center, n, r) = axis(at: date), let next = axis(at: date.addingTimeInterval(step)) else { return nil }
        guard let c = center.hit, let c2 = next.0.hit else { return nil }
        // Unit vector across the track: perpendicular to the shadow axis and the ground motion.
        let across = normalize(cross(n, c2 - c))
        let offset = across * (abs(r) / kmPerAU)
        let north = Ray(origin: center.origin + offset, direction: n).hit
        let south = Ray(origin: center.origin - offset, direction: n).hit
        let t = SkyEngine.time(date)
        func geo(_ v: SIMD3<Double>) -> (lat: Double, lon: Double) {
            var vec = astro_vector_t(status: ASTRO_SUCCESS, x: v.x, y: v.y, z: v.z, t: t)
            let o = Astronomy_VectorObserver(&vec, EQUATOR_OF_DATE)
            return (o.latitude, o.longitude)
        }
        var a = geo(north ?? c), b = geo(south ?? c)
        if a.lat < b.lat { swap(&a, &b) }
        let width = (north != nil && south != nil) ? length(north! - south!) * kmPerAU : 2 * abs(r)
        return Point(date: date, center: geo(c), north: north == nil ? nil : a, south: south == nil ? nil : b, widthKm: width)
    }

    struct Ray {
        var origin: SIMD3<Double>
        var direction: SIMD3<Double>

        /// First intersection with the Earth's ellipsoid, AU, equator-of-date axes.
        var hit: SIMD3<Double>? {
            let k = 1 / (1 - EclipsePath.earthF)
            let o = SIMD3(origin.x, origin.y, origin.z * k), d = SIMD3(direction.x, direction.y, direction.z * k)
            let a = EclipsePath.earthA / EclipsePath.kmPerAU
            let A = dot(d, d), B = 2 * dot(o, d), C = dot(o, o) - a * a
            let disc = B * B - 4 * A * C
            guard disc >= 0 else { return nil }
            let s = (-B - disc.squareRoot()) / (2 * A)
            guard s > 0 else { return nil }
            let p = o + d * s
            return SIMD3(p.x, p.y, p.z / k)
        }
    }

    /// Shadow axis from the Moon away from the Sun (equator of date), its direction,
    /// and the umbra radius where it meets the Earth (km; negative for the antumbra).
    static func axis(at date: Date) -> (Ray, SIMD3<Double>, Double)? {
        var t = SkyEngine.time(date)
        let rot = Astronomy_Rotation_EQJ_EQD(&t)
        let sun = Astronomy_RotateVector(rot, Astronomy_GeoVector(BODY_SUN, t, NO_ABERRATION))
        let moon = Astronomy_RotateVector(rot, Astronomy_GeoMoon(t))
        let s = SIMD3(sun.x, sun.y, sun.z), m = SIMD3(moon.x, moon.y, moon.z)
        let n = normalize(m - s)
        let ray = Ray(origin: m, direction: n)
        guard let hit = ray.hit else { return nil }
        let D = length(m - s) * kmPerAU
        let L = length(hit - m) * kmPerAU
        let r = moonRadiusKm - L * (sunRadiusKm - moonRadiusKm) / D
        return (ray, n, r)
    }
}

private func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { (a * b).sum() }
private func length(_ a: SIMD3<Double>) -> Double { dot(a, a).squareRoot() }
private func normalize(_ a: SIMD3<Double>) -> SIMD3<Double> { a / length(a) }
private func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

/// A solar eclipse as seen from one place.
public struct LocalEclipse: Sendable {
    public var kind: String
    public var obscuration: Double
    public var partialBegin: Date
    public var centralBegin: Date?
    public var peak: Date
    public var centralEnd: Date?
    public var partialEnd: Date
    /// Sun's altitude at the peak, degrees.
    public var peakAltitude: Double

    /// The observer's view of the solar eclipse peaking within six hours of `date`, if any part is above the horizon.
    public static func at(_ observer: Observer, near date: Date) -> LocalEclipse? {
        SkyEngine.lock.lock()
        defer { SkyEngine.lock.unlock() }
        let l = Astronomy_SearchLocalSolarEclipse(SkyEngine.time(date.addingTimeInterval(-6 * 3600)), observer.astro)
        guard l.status == ASTRO_SUCCESS else { return nil }
        let peak = SkyEngine.date(l.peak.time)
        guard abs(peak.timeIntervalSince(date)) < 6 * 3600 else { return nil }
        guard l.partial_begin.altitude > 0 || l.peak.altitude > 0 || l.partial_end.altitude > 0 else { return nil }
        let central = l.kind == ECLIPSE_TOTAL || l.kind == ECLIPSE_ANNULAR
        let partial = { (s: Shadow) in s.p - s.r }, inner = { (s: Shadow) in abs(s.k) - s.r }
        return LocalEclipse(
            kind: SkyEngine.eclipseKind(l.kind), obscuration: l.obscuration,
            partialBegin: refine(SkyEngine.date(l.partial_begin.time), observer, partial),
            centralBegin: central ? refine(SkyEngine.date(l.total_begin.time), observer, inner) : nil,
            peak: peak,
            centralEnd: central ? refine(SkyEngine.date(l.total_end.time), observer, inner) : nil,
            partialEnd: refine(SkyEngine.date(l.partial_end.time), observer, partial),
            peakAltitude: l.peak.altitude
        )
    }

    /// Moon radii for the partial and total contacts, km: k = 0.2725076 and the smaller k = 0.272281 that NASA's
    /// eclipse predictions use for totality to allow for valleys on the limb, times 6378.137 km.
    /// Astronomy Engine uses 1737.4 km for both.
    static let moonRadiusPartialKm = 1_738.09, moonRadiusTotalKm = 1_736.64

    /// The Moon's shadow at the observer, as Astronomy Engine computes it for local eclipses: the observer's
    /// distance from the shadow axis and the umbra and penumbra radii at the observer, km.
    struct Shadow {
        var r: Double
        var k: Double
        var p: Double
    }

    static func shadow(at date: Date, from observer: Observer) -> Shadow {
        var t = SkyEngine.time(date)
        let o = Astronomy_ObserverVector(&t, observer.astro, EQUATOR_J2000)
        let s = Astronomy_GeoVector(BODY_SUN, t, ABERRATION)
        let m = Astronomy_GeoMoon(t)
        let target = SIMD3(o.x - m.x, o.y - m.y, o.z - m.z), dir = SIMD3(m.x - s.x, m.y - s.y, m.z - s.z)
        let u = dot(dir, target) / dot(dir, dir)
        let sun = EclipsePath.sunRadiusKm
        return Shadow(
            r: length(dir * u - target) * EclipsePath.kmPerAU,
            k: sun - (1 + u) * (sun - moonRadiusTotalKm),
            p: -sun + (1 + u) * (sun + moonRadiusPartialKm)
        )
    }

    /// Moves a contact found to Astronomy Engine's 1 s search tolerance, with its single Moon radius, to the radii above,
    /// to 0.05 s, by bisecting where `edge` changes sign.
    static func refine(_ near: Date, _ observer: Observer, _ edge: (Shadow) -> Double) -> Date {
        var a = near.addingTimeInterval(-5), b = near.addingTimeInterval(5)
        var fa = edge(shadow(at: a, from: observer))
        guard fa * edge(shadow(at: b, from: observer)) < 0 else { return near }
        while b.timeIntervalSince(a) > 0.05 {
            let mid = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            let f = edge(shadow(at: mid, from: observer))
            if (f < 0) == (fa < 0) { a = mid; fa = f } else { b = mid }
        }
        return a.addingTimeInterval(b.timeIntervalSince(a) / 2)
    }
}
