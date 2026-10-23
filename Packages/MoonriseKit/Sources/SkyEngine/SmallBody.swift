import Foundation

/// A comet or asteroid from JPL's Small-Body Database, propagated as a two-body orbit from its perihelion: elliptic,
/// near-parabolic or hyperbolic. Planetary perturbations are ignored, so positions drift by up to a degree or so
/// over a year from the elements' epoch.
public struct SmallBody: Sendable, Equatable, Codable, Identifiable {
    public enum Brightness: Sendable, Equatable, Codable {
        /// Total magnitude M1 and slope K1: m = M1 + 5 log Δ + K1 log r.
        case comet(m1: Double, k1: Double)
        /// H–G system.
        case asteroid(h: Double, g: Double)
    }

    public var name: String
    /// Perihelion distance, AU; eccentricity; inclination, ascending node and argument of perihelion, degrees
    /// (J2000 ecliptic); time of perihelion, TDB Julian date.
    public var q: Double, e: Double, i: Double, node: Double, peri: Double, tp: Double
    public var brightness: Brightness
    public var id: String { name }

    public init(name: String, q: Double, e: Double, i: Double, node: Double, peri: Double, tp: Double, brightness: Brightness) {
        self.name = name; self.q = q; self.e = e; self.i = i; self.node = node; self.peri = peri; self.tp = tp; self.brightness = brightness
    }

    public var isComet: Bool { if case .comet = brightness { true } else { false } }

    /// Gaussian gravitational constant, radians per day.
    static let k = 0.01720209895

    /// Heliocentric position in AU on J2000 ecliptic axes.
    public func position(at date: Date) -> SIMD3<Double> {
        let dt = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - tp
        let (x, y) = abs(e - 1) < 1e-4 ? nearParabolicPosition(dt) : e < 1 ? ellipticPosition(dt) : hyperbolicPosition(dt)
        let r = Double.pi / 180
        let (cO, sO) = (cos(node * r), sin(node * r)), (cw, sw) = (cos(peri * r), sin(peri * r)), (ci, si) = (cos(i * r), sin(i * r))
        return SIMD3(
            (cO * cw - sO * sw * ci) * x + (-cO * sw - sO * cw * ci) * y,
            (sO * cw + cO * sw * ci) * x + (-sO * sw + cO * cw * ci) * y,
            (sw * si) * x + (cw * si) * y
        )
    }

    /// In-plane position for an eccentricity near 1, by Barker's equation:
    /// s + s³/3 = k Δt / √(2q³), s = tan(ν/2).
    private func nearParabolicPosition(_ dt: Double) -> (x: Double, y: Double) {
        let w = 3 * Self.k * dt / (2 * q * q * q).squareRoot()
        let c = cbrt(w / 2 + (w * w / 4 + 1).squareRoot())
        let s = c - 1 / c
        return (q * (1 - s * s), 2 * q * s)
    }

    /// In-plane position on an ellipse, solving Kepler's equation by Newton's method.
    private func ellipticPosition(_ dt: Double) -> (x: Double, y: Double) {
        let a = q / (1 - e), m = Self.k * dt / pow(a, 1.5)
        let mm = remainder(m, 2 * .pi)
        var E = e < 0.8 ? mm : .pi * (mm < 0 ? -1 : 1)
        for _ in 0..<60 {
            let d = (E - e * sin(E) - mm) / (1 - e * cos(E))
            E -= d
            if abs(d) < 1e-13 { break }
        }
        return (a * (cos(E) - e), a * (1 - e * e).squareRoot() * sin(E))
    }

    /// In-plane position on a hyperbola, solving the hyperbolic Kepler equation by Newton's method.
    private func hyperbolicPosition(_ dt: Double) -> (x: Double, y: Double) {
        let a = q / (e - 1), m = Self.k * dt / pow(a, 1.5)
        var h = asinh(m / e)
        for _ in 0..<60 {
            let d = (e * sinh(h) - h - m) / (e * cosh(h) - 1)
            h -= d
            if abs(d) < 1e-13 { break }
        }
        return (a * (e - cosh(h)), a * (e * e - 1).squareRoot() * sinh(h))
    }

    /// Astrometric J2000 right ascension and declination (degrees), distances (AU) and magnitude from Earth at `date`;
    /// light time is ignored.
    public func apparent(at date: Date) throws -> (ra: Double, dec: Double, r: Double, delta: Double, magnitude: Double) {
        let p = position(at: date), earth = try SkyEngine.heliocentricEarth(at: date)
        let g = p - earth
        let eps = 23.4392911 * Double.pi / 180
        let eq = SIMD3(g.x, g.y * cos(eps) - g.z * sin(eps), g.y * sin(eps) + g.z * cos(eps))
        let delta = (eq * eq).sum().squareRoot(), r = (p * p).sum().squareRoot(), big = (earth * earth).sum().squareRoot()
        var ra = atan2(eq.y, eq.x) * 180 / .pi
        if ra < 0 { ra += 360 }
        let dec = asin(eq.z / delta) * 180 / .pi
        let m: Double
        switch brightness {
        case .comet(let m1, let k1):
            m = m1 + 5 * log10(delta) + k1 * log10(r)
        case .asteroid(let h, let gSlope):
            let alpha = acos(max(-1, min(1, (r * r + delta * delta - big * big) / (2 * r * delta))))
            let t = tan(alpha / 2)
            let phi1 = exp(-3.33 * pow(t, 0.63)), phi2 = exp(-1.87 * pow(t, 1.22))
            m = h + 5 * log10(r * delta) - 2.5 * log10((1 - gSlope) * phi1 + gSlope * phi2)
        }
        return (ra, dec, r, delta, m)
    }
}
