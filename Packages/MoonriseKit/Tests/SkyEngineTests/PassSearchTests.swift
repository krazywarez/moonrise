import CAstronomy
import Foundation
import Testing
@testable import SkyEngine

/// The search `passes(of:)` replaced: a sample every 20 s whatever the altitude.
private func everyTwentySeconds(_ elements: OrbitalElements, from start: Date, observer: Observer) -> [SatellitePass] {
    guard let sgp = try? SGP4(elements) else { return [] }
    var out: [SatellitePass] = []
    var current: (rise: Date, riseAz: Double, peak: Date, maxAlt: Double, visible: Bool)?
    var lastAz = 0.0
    var t = start
    while t <= start.addingTimeInterval(72 * 3600) {
        guard let r = sgp.position(at: t) else { break }
        let h = SkyEngine.lookAngles(teme: r, at: t, from: observer)
        if h.altitude >= 0 {
            if current == nil { current = (t, h.azimuth, t, h.altitude, false) }
            if h.altitude > current!.maxAlt { current!.maxAlt = h.altitude; current!.peak = t }
            if !current!.visible, h.altitude >= 10 {
                var tt = SkyEngine.time(t)
                let sun = Astronomy_Equator(BODY_SUN, &tt, observer.astro, EQUATOR_OF_DATE, ABERRATION)
                let sunAlt = Astronomy_Horizon(&tt, observer.astro, sun.ra, sun.dec, REFRACTION_NORMAL).altitude
                if sunAlt < -6, SkyEngine.sunlit(r, sun: SkyEngine.sunDirection(t)) { current!.visible = true }
            }
            lastAz = h.azimuth
        } else if let c = current {
            if c.maxAlt >= 10 {
                out.append(SatellitePass(name: elements.OBJECT_NAME, rise: c.rise, set: t, peak: c.peak, maxAltitude: c.maxAlt, riseAzimuth: c.riseAz, setAzimuth: lastAz, visible: c.visible))
            }
            current = nil
        }
        t = t.addingTimeInterval(20)
    }
    return out
}

private struct LCG {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

/// ISS, Tiangong and Hubble, 155 low-orbit objects at the visual group's usual inclinations, and a Starlink train with
/// its second stage, all searched from 2026-10-20 18:00 UTC.
private let fixtures: [OrbitalElements] = {
    var out = [
        OrbitalElements(name: "ISS (ZARYA)", norad: 25544, epoch: "2026-10-18T03:28:15.076416", meanMotion: 15.48918166, eccentricity: 0.000678,
                        inclination: 51.6328, raan: 51.6259, argPerigee: 277.7856, meanAnomaly: 82.2363, bstar: 0.00014456),
        OrbitalElements(name: "CSS (TIANHE)", norad: 48274, epoch: "2026-10-18T05:11:02.000000", meanMotion: 15.60, eccentricity: 0.0005,
                        inclination: 41.47, raan: 120.0, argPerigee: 30.0, meanAnomaly: 200.0, bstar: 0.0002),
        OrbitalElements(name: "HST", norad: 20580, epoch: "2026-10-18T09:00:00.000000", meanMotion: 15.28, eccentricity: 0.0002,
                        inclination: 28.47, raan: 300.0, argPerigee: 90.0, meanAnomaly: 10.0, bstar: 0.00002),
        OrbitalElements(name: "Starlink train (Group 15-25)", norad: 66001, epoch: "2026-10-20T10:10:01.123456", meanMotion: 15.91, eccentricity: 0.0012,
                        inclination: 53.05, raan: 200.0, argPerigee: 270.0, meanAnomaly: 90.0, bstar: 0.0006),
        OrbitalElements(name: "FALCON 9 R/B", norad: 66030, epoch: "2026-10-20T10:10:01.123456", meanMotion: 15.905, eccentricity: 0.0012,
                        inclination: 53.05, raan: 200.0, argPerigee: 270.0, meanAnomaly: 88.0, bstar: 0.0006),
    ]
    var r = LCG(state: 42)
    let incs = [71.0, 74.0, 81.2, 82.5, 83.0, 98.2, 65.0, 56.0, 50.0]
    for i in 0..<155 {
        let k = Int(r.next() * Double(incs.count))
        out.append(OrbitalElements(name: "OBJECT \(i)", norad: 10_000 + i, epoch: "2026-10-19T12:00:00.000000",
                                   meanMotion: r.range(13.9, 15.3), eccentricity: r.range(0.0005, 0.02), inclination: incs[k] + r.range(-0.5, 0.5),
                                   raan: r.range(0, 360), argPerigee: r.range(0, 360), meanAnomaly: r.range(0, 360), bstar: r.range(1e-5, 2e-4)))
    }
    return out
}()

@Test(arguments: [
    ("equator", Observer(latitude: 0.18, longitude: -78.47)),
    ("mid-latitude", chicago),
    ("high latitude", Observer(latitude: 69.65, longitude: 18.96)),
])
func adaptiveStepsFindTheSamePasses(_ place: String, _ observer: Observer) throws {
    let start = Date(timeIntervalSince1970: 1_792_519_200)
    // Vanguard 1 (e 0.19) from its epoch, for an orbit whose angular rate varies.
    let cases = fixtures.map { ($0, start) } + [(vanguard, try #require(vanguard.epochDate))]
    var count = 0
    for (elements, from) in cases {
        let old = everyTwentySeconds(elements, from: from, observer: observer)
        let new = SkyEngine.passes(of: elements, from: from, hours: 72, observer: observer)
        try #require(new.count == old.count, "\(place), \(elements.OBJECT_NAME): \(new.count) passes, \(old.count) with 20 s steps")
        for (a, b) in zip(new, old) {
            #expect(abs(a.rise.timeIntervalSince(b.rise)) <= 1 && abs(a.peak.timeIntervalSince(b.peak)) <= 1 && abs(a.set.timeIntervalSince(b.set)) <= 1,
                    "\(place), \(elements.OBJECT_NAME): \(a.rise)–\(a.set), \(b.rise)–\(b.set) with 20 s steps")
            #expect(a.visible == b.visible && abs(a.maxAltitude - b.maxAltitude) < 1e-6)
        }
        count += old.count
    }
    #expect(count > 1000, "\(count) passes")
}
