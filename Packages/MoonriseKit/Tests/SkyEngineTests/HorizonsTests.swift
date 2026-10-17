import Foundation
import Testing
@testable import SkyEngine

// Reference values from JPL Horizons (ssd.jpl.nasa.gov/api/horizons.api), fetched 2026-10-17.
// Observer table: site -87.6298 E, 41.8781 N, 0 km; 2026-10-17 02:00 UT; quantities 2 (apparent
// RA/Dec, degrees) and 4 (airless apparent azimuth/elevation).
// Vector table: CENTER 500@10, REF_PLANE FRAME, 2026-10-17 00:00 UT, AU.

let chicago = Observer(latitude: 41.8781, longitude: -87.6298)
let observed = Date(timeIntervalSince1970: 1_792_202_400) // 2026-10-17T02:00:00Z
let vectorEpoch = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17T00:00:00Z

struct HorizonsRow {
    var body: Body
    var raDegrees: Double
    var dec: Double
    var azimuth: Double
    var altitude: Double
}

let observerRows: [HorizonsRow] = [
    HorizonsRow(body: .moon, raDegrees: 276.63979, dec: -28.01156, azimuth: 223.832359, altitude: 5.580273),
    HorizonsRow(body: .mars, raDegrees: 133.60867, dec: 18.78232, azimuth: 15.406574, altitude: -27.902306),
    HorizonsRow(body: .jupiter, raDegrees: 144.84484, dec: 14.69461, azimuth: 3.616329, altitude: -33.353920),
    HorizonsRow(body: .saturn, raDegrees: 10.55474, dec: 1.59612, azimuth: 124.822854, altitude: 34.510943),
]

/// One arcminute, Astronomy Engine's stated accuracy.
let arcminute = 1.0 / 60

func angularDifference(_ a: Double, _ b: Double) -> Double {
    abs(remainder(a - b, 360))
}

@Test(arguments: observerRows)
func apparentEquatorialMatchesHorizons(_ row: HorizonsRow) throws {
    let eq = try SkyEngine.equatorial(row.body, at: observed, from: chicago)
    let raError = angularDifference(eq.rightAscension * 15, row.raDegrees) * cos(row.dec * .pi / 180)
    #expect(raError < arcminute, "\(row.body) RA off by \(raError * 60)'")
    #expect(abs(eq.declination - row.dec) < arcminute, "\(row.body) Dec off by \(abs(eq.declination - row.dec) * 60)'")
}

@Test(arguments: observerRows)
func horizontalMatchesHorizons(_ row: HorizonsRow) throws {
    let hor = try SkyEngine.horizontal(row.body, at: observed, from: chicago)
    let azError = angularDifference(hor.azimuth, row.azimuth) * cos(row.altitude * .pi / 180)
    #expect(azError < arcminute, "\(row.body) azimuth off by \(azError * 60)'")
    #expect(abs(hor.altitude - row.altitude) < arcminute, "\(row.body) altitude off by \(abs(hor.altitude - row.altitude) * 60)'")
}

@Test(arguments: [
    (Body.jupiter, SIMD3(-3.581981680856141, 3.573182031399209, 1.618755638647523)),
    (Body.saturn, SIMD3(9.237054585455835, 1.860186986025053, 0.3705349659085789)),
])
func heliocentricMatchesHorizons(_ body: Body, _ expected: SIMD3<Double>) throws {
    let v = try SkyEngine.heliocentric(body, at: vectorEpoch)
    let d = v - expected
    let error = (d * d).sum().squareRoot()
    let angle = error / (expected * expected).sum().squareRoot() * 180 / .pi
    #expect(angle < arcminute, "\(body) off by \(error) AU (\(angle * 3600)\")")
}

@Test func moonPhaseIsWaxing() throws {
    let phase = try SkyEngine.moonPhase(at: observed)
    #expect(phase > 0 && phase < 180)
}
