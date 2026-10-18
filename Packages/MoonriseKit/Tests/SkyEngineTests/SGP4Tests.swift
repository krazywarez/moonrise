import Foundation
import Testing
@testable import SkyEngine

// Vallado's SGP4 verification case for satellite 00005 (SGP4-VER.TLE / tcppver.out):
// 1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753
// 2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667
// Epoch 2000 day 179.78495062 = 2000-06-27T18:50:19.733568Z.
let vanguard = OrbitalElements(name: "00005", norad: 5, epoch: "2000-06-27T18:50:19.733568",
                               meanMotion: 10.82419157, eccentricity: 0.1859667, inclination: 34.2682,
                               raan: 348.7242, argPerigee: 331.7664, meanAnomaly: 19.3264, bstar: 0.28098e-4)

func dist(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { let d = a - b; return (d * d).sum().squareRoot() }

@Test(arguments: [
    (0.0, SIMD3(7022.46529266, -1400.08296755, 0.03995155), SIMD3(1.893841015, 6.405893759, 4.534807250)),
    (360.0, SIMD3(-7154.03120202, -3783.17682504, -3536.19412294), SIMD3(4.741887409, -4.151817765, -2.093935425)),
    (720.0, SIMD3(-7134.59340119, 6531.68641334, 3260.27186483), SIMD3(-4.113793027, -2.911922039, -2.557327851)),
])
func matchesValladoVerification(_ t: Double, _ r: SIMD3<Double>, _ v: SIMD3<Double>) throws {
    let s = try SGP4(vanguard)
    let out = try #require(s.propagate(minutes: t))
    #expect(dist(out.r, r) < 0.01, "t=\(t): r off by \(dist(out.r, r)) km")
    #expect(dist(out.v, v) < 1e-5, "t=\(t): v off by \(dist(out.v, v)) km/s")
}

@Test func epochParsesFractionalSeconds() throws {
    let d = try #require(vanguard.epochDate)
    #expect(abs(d.timeIntervalSince1970 - 962_131_819.733568) < 1e-3)
}

@Test func issIsInLowOrbit() throws {
    // CelesTrak GP for the ISS, 2026-10-18.
    let iss = OrbitalElements(name: "ISS (ZARYA)", norad: 25544, epoch: "2026-10-18T03:28:15.076416",
                              meanMotion: 15.48918166, eccentricity: 0.000678, inclination: 51.6328,
                              raan: 51.6259, argPerigee: 277.7856, meanAnomaly: 82.2363, bstar: 0.00014456)
    let s = try SGP4(iss)
    let r = try #require(s.propagate(minutes: 60)?.r)
    let altitude = (r * r).sum().squareRoot() - 6378.135
    #expect(altitude > 380 && altitude < 450, "\(altitude) km")
}

@Test func gmstAtJ2000() {
    // GMST at 2000-01-01 12:00 UT1 is 280.46061837 degrees.
    let g = SkyEngine.gmst(Date(timeIntervalSince1970: 946_728_000)) * 180 / .pi
    #expect(abs(g - 280.46061837) < 1e-4)
}

@Test func issPassesOverChicago() throws {
    let iss = OrbitalElements(name: "ISS (ZARYA)", norad: 25544, epoch: "2026-10-18T03:28:15.076416",
                              meanMotion: 15.48918166, eccentricity: 0.000678, inclination: 51.6328,
                              raan: 51.6259, argPerigee: 277.7856, meanAnomaly: 82.2363, bstar: 0.00014456)
    let start = try #require(iss.epochDate)
    let passes = SkyEngine.passes(of: iss, from: start, hours: 72, observer: chicago)
    // The ISS (51.6° inclination) passes over 42° N several times a day.
    #expect(passes.count >= 6, "\(passes.count) passes")
    for p in passes {
        #expect(p.maxAltitude >= 10 && p.maxAltitude <= 90)
        let minutes = p.set.timeIntervalSince(p.rise) / 60
        #expect(minutes > 2 && minutes < 12, "\(minutes) min")
    }
}
