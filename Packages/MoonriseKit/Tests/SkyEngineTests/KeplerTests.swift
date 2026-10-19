import Foundation
import Testing
@testable import SkyEngine

private func jd(_ jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400) }
private func auDist(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { ((a - b) * (a - b)).sum().squareRoot() }

@Test func ceresMatchesHorizons() throws {
    // JPL Horizons, heliocentric J2000 ecliptic, 2026-10-19 00:00 TDB.
    let ceres = try #require(KeplerOrbit.dwarfPlanets.first { $0.id == "ceres" })
    let p = ceres.position(at: jd(2461332.5))
    #expect(auDist(p, SIMD3(0.09160098, 2.65726102, 0.06724773)) < 0.003)
}

@Test func halleyMatchesHorizons() throws {
    let halley = try #require(KeplerOrbit.comets.first { $0.id == "halley" })
    // At its 1986 perihelion: within 0.05 AU, about a day of its motion there (Horizons uses a perturbed solution).
    #expect(auDist(halley.position(at: jd(2446470.5)), SIMD3(0.34233380, -0.44659254, 0.16779698)) < 0.05)
    // ...and near aphelion now, where two-body drift is a few tenths of an AU at 36 AU.
    #expect(auDist(halley.position(at: jd(2461332.5)), SIMD3(-19.34593976, 27.47052259, -9.85160687)) < 1)
}

@Test func showersFindParentsAndPeaks() {
    let perseids = MeteorShower.major.first { $0.name == "Perseids" }!
    #expect(perseids.parent == "swift-tuttle")
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let aug10 = cal.date(from: DateComponents(year: 2027, month: 8, day: 10, hour: 12))!
    #expect(abs(perseids.daysToPeak(from: aug10, calendar: cal) - 2) < 0.01)
    let dec30 = cal.date(from: DateComponents(year: 2026, month: 12, day: 30, hour: 12))!
    let quadrantids = MeteorShower.major.first { $0.name == "Quadrantids" }!
    #expect(abs(quadrantids.daysToPeak(from: dec30, calendar: cal) - 4) < 0.01)
}

@Test func galileanMoonDistances() {
    let km = SkyEngine.galileanMoons(at: Date(timeIntervalSince1970: 1_792_400_000)).map { ($0 * $0).sum().squareRoot() * 1.495978707e8 }
    // Mean distances 421,800 / 671,100 / 1,070,400 / 1,882,700 km; orbits are nearly circular.
    for (d, mean) in zip(km, [421_800.0, 671_100, 1_070_400, 1_882_700]) { #expect(abs(d - mean) / mean < 0.02) }
}

@Test func enckeReturnsFeb2027() throws {
    // Short periods are where two-body prediction holds; JPL lists Encke's next perihelion as 2027-02-10.
    let encke = try #require(KeplerOrbit.comets.first { $0.id == "encke" })
    let next = encke.nextPerihelion(after: Date(timeIntervalSince1970: 1_792_400_000))
    #expect(abs(next.timeIntervalSince(Date(timeIntervalSince1970: 1_802_217_600)) / 86_400) < 3)
}

@Test func halleyPathSpansItsOrbit() throws {
    let halley = try #require(KeplerOrbit.comets.first { $0.id == "halley" })
    let r = halley.orbitPath().map { ($0 * $0).sum().squareRoot() }
    #expect(abs(r.min()! - 0.575) < 0.001 && abs(r.max()! - 35.28) < 0.01)
}
