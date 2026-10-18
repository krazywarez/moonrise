import CAstronomy
import Foundation

public struct SatellitePass: Sendable, Identifiable, Equatable {
    public var name: String
    public var rise: Date
    public var set: Date
    public var peak: Date
    public var maxAltitude: Double
    public var riseAzimuth: Double
    public var setAzimuth: Double
    /// Sunlit while the observer's sky is dark: can be seen with the eye.
    public var visible: Bool
    public var id: String { "\(name)-\(Int(rise.timeIntervalSince1970))" }
}

extension SkyEngine {
    /// Greenwich mean sidereal time in radians (IAU 1982, as used with SGP4's TEME frame).
    static func gmst(_ date: Date) -> Double {
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (jd - 2_451_545) / 36_525
        var s = -6.2e-6 * t * t * t + 0.093104 * t * t + (876_600 * 3600 + 8_640_184.812866) * t + 67_310.54841
        s = fmod(s * Double.pi / 180 / 240, 2 * Double.pi)
        return s < 0 ? s + 2 * Double.pi : s
    }

    /// Observer position in an Earth-fixed frame (km), WGS-84.
    static func observerECEF(_ o: Observer) -> SIMD3<Double> {
        let a = 6378.137, f = 1 / 298.257223563
        let e2 = f * (2 - f)
        let lat = o.latitude * .pi / 180, lon = o.longitude * .pi / 180, h = o.height / 1000
        let n = a / (1 - e2 * sin(lat) * sin(lat)).squareRoot()
        return SIMD3((n + h) * cos(lat) * cos(lon), (n + h) * cos(lat) * sin(lon), (n * (1 - e2) + h) * sin(lat))
    }

    /// Altitude and azimuth of a TEME position as seen by the observer.
    static func lookAngles(teme r: SIMD3<Double>, at date: Date, from o: Observer) -> Horizontal {
        let g = gmst(date)
        let ecef = SIMD3(r.x * cos(g) + r.y * sin(g), -r.x * sin(g) + r.y * cos(g), r.z)
        let d = ecef - observerECEF(o)
        let lat = o.latitude * .pi / 180, lon = o.longitude * .pi / 180
        let south = sin(lat) * cos(lon) * d.x + sin(lat) * sin(lon) * d.y - cos(lat) * d.z
        let east = -sin(lon) * d.x + cos(lon) * d.y
        let up = cos(lat) * cos(lon) * d.x + cos(lat) * sin(lon) * d.y + sin(lat) * d.z
        let range = (d * d).sum().squareRoot()
        var az = atan2(east, -south) * 180 / .pi
        if az < 0 { az += 360 }
        return Horizontal(altitude: asin(up / range) * 180 / .pi, azimuth: az)
    }

    /// Unit vector to the Sun on equator-of-date axes, close enough to TEME for Earth's shadow.
    static func sunDirection(_ date: Date) -> SIMD3<Double> {
        var t = time(date)
        let v = Astronomy_GeoVector(BODY_SUN, t, NO_ABERRATION)
        let rot = Astronomy_Rotation_EQJ_EQD(&t)
        let e = Astronomy_RotateVector(rot, v)
        let s = SIMD3(e.x, e.y, e.z)
        return s / (s * s).sum().squareRoot()
    }

    /// Cylindrical Earth-shadow test.
    static func sunlit(_ r: SIMD3<Double>, sun: SIMD3<Double>) -> Bool {
        let along = (r * sun).sum()
        if along > 0 { return true }
        let perp = r - along * sun
        return (perp * perp).sum().squareRoot() > 6378.135
    }

    /// Passes above `minAltitude` in the next `hours`, sampled every 20 s.
    public static func passes(of elements: OrbitalElements, from start: Date, hours: Double = 72, observer: Observer, minAltitude: Double = 10) -> [SatellitePass] {
        guard let sgp = try? SGP4(elements) else { return [] }
        lock.lock()
        defer { lock.unlock() }
        var out: [SatellitePass] = []
        var current: (rise: Date, riseAz: Double, peak: Date, maxAlt: Double, visible: Bool)?
        var lastAz = 0.0
        let step = 20.0
        var t = start
        let end = start.addingTimeInterval(hours * 3600)
        while t <= end {
            guard let r = sgp.position(at: t) else { break }
            let h = lookAngles(teme: r, at: t, from: observer)
            if h.altitude >= 0 {
                if current == nil { current = (t, h.azimuth, t, h.altitude, false) }
                if h.altitude > current!.maxAlt { current!.maxAlt = h.altitude; current!.peak = t }
                if !current!.visible, h.altitude >= minAltitude {
                    var tt = time(t)
                    let sun = Astronomy_Equator(BODY_SUN, &tt, observer.astro, EQUATOR_OF_DATE, ABERRATION)
                    let sunAlt = Astronomy_Horizon(&tt, observer.astro, sun.ra, sun.dec, REFRACTION_NORMAL).altitude
                    if sunAlt < -6, sunlit(r, sun: sunDirection(t)) { current!.visible = true }
                }
                lastAz = h.azimuth
            } else if let c = current {
                if c.maxAlt >= minAltitude {
                    out.append(SatellitePass(name: elements.OBJECT_NAME, rise: c.rise, set: t, peak: c.peak, maxAltitude: c.maxAlt, riseAzimuth: c.riseAz, setAzimuth: lastAz, visible: c.visible))
                }
                current = nil
            }
            t = t.addingTimeInterval(step)
        }
        return out
    }
}
