import Foundation
import Testing
@testable import SkyEngine

private let date = Date(timeIntervalSince1970: 1_792_627_200) // 2026-10-22 00:00 UTC

private func separation(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
    let r = Double.pi / 180
    return acos(min(1, sin(a.1 * r) * sin(b.1 * r) + cos(a.1 * r) * cos(b.1 * r) * cos((a.0 - b.0) * r))) / r
}

@Test func ceresAgainstHorizons() throws {
    // SBDB elements fetched 2026-10-22; Horizons: RA 112.46538, Dec 23.64840, V 8.400, r 2.65745, Δ 2.33374.
    let ceres = SmallBody(name: "1 Ceres", q: 2.545, e: 0.0797, i: 10.59, node: 80.25, peri: 73.29, tp: 2461599.84, brightness: .asteroid(h: 3.34, g: 0.12))
    let a = try ceres.apparent(at: date)
    #expect(separation((a.ra, a.dec), (112.46538, 23.64840)) < 1)
    #expect(abs(a.r - 2.65745) < 0.02 && abs(a.delta - 2.33374) < 0.02)
    #expect(abs(a.magnitude - 8.40) < 0.3)
}

@Test func cometAgainstHorizons() throws {
    // 24P/Schaumasse; Horizons: RA 245.75004, Dec −21.65566, r 3.23966, Δ 3.94765.
    let c = SmallBody(name: "24P/Schaumasse", q: 1.185, e: 0.7079, i: 11.50, node: 78.29, peri: 58.48, tp: 2461049.06, brightness: .comet(m1: 14.6, k1: 8))
    let a = try c.apparent(at: date)
    #expect(separation((a.ra, a.dec), (245.75004, -21.65566)) < 1)
    #expect(abs(a.r - 3.23966) < 0.03 && abs(a.delta - 3.94765) < 0.03)
}

@Test func parabolicAndHyperbolicOrbitsMeetTheEllipseAtPerihelion() {
    for e in [0.99999, 1.0, 1.00001, 1.5] {
        let b = SmallBody(name: "x", q: 0.5, e: e, i: 0, node: 0, peri: 0, tp: 2_461_000, brightness: .comet(m1: 5, k1: 10))
        let atPerihelion = b.position(at: Date(timeIntervalSince1970: (2_461_000 - 2_440_587.5) * 86_400))
        #expect(abs(atPerihelion.x - 0.5) < 1e-6 && abs(atPerihelion.y) < 1e-6)
        let later = b.position(at: Date(timeIntervalSince1970: (2_461_100 - 2_440_587.5) * 86_400))
        let r = (later * later).sum().squareRoot()
        #expect(r > 0.5 && later.y > 0, "e \(e): r \(r)")
    }
}
