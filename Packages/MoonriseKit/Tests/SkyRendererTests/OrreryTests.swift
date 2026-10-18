import Foundation
import SkyEngine
import Testing
@testable import SkyRenderer

let october2026 = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17T00:00:00Z

@Test func spacecraftLoadAndInterpolate() throws {
    #expect(Spacecraft.all.map(\.name) == ["Voyager 1", "Voyager 2", "Pioneer 10", "Pioneer 11", "New Horizons"])
    let v1 = try #require(Spacecraft.all.first { $0.name == "Voyager 1" })
    let p = try #require(v1.position(at: october2026))
    let au = (p * p).sum().squareRoot()
    // Voyager 1 is about 170 AU from the Sun in late 2026 and about 35° north of the
    // ecliptic, so its distance projected on the ecliptic plane is about 140 AU.
    #expect(au > 130 && au < 150, "\(au) AU")
    #expect(v1.position(at: Date(timeIntervalSince1970: 0)) == nil)
}

@Test func earthIsOneAUFromTheSun() throws {
    let e = try SkyEngine.heliocentricEarth(at: october2026)
    let au = (e * e).sum().squareRoot()
    #expect(abs(au - 1) < 0.02)
    #expect(abs(e.z) < 1e-3)
}

@Test func orreryScaleIsMonotonic() {
    let s = OrreryScale(size: CGSize(width: 400, height: 400))
    #expect(s.radius(0.5) < s.radius(1))
    #expect(s.radius(1) < s.radius(5))
    #expect(s.radius(30) < s.radius(170))
    #expect(abs(s.radius(230) - 192) < 1e-9)
}

@Test func voyager1TrueDistance() throws {
    let v1 = try #require(Spacecraft.all.first { $0.name == "Voyager 1" })
    let d = try #require(v1.distance(at: october2026))
    #expect(d > 165 && d < 175, "\(d) AU")
}
