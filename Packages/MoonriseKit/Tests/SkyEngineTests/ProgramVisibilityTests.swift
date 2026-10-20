import Foundation
import Testing
@testable import SkyEngine

@Test func bestInDarknessFromChicago() throws {
    let m31 = (ra: 10.68471, dec: 41.26875)
    let m7 = (ra: 268.46325, dec: -34.79283)
    let m104 = (ra: 189.99763, dec: -11.62305)
    let t = try Tonight(at: observed, from: chicago)
    let best = try SkyEngine.bestInDarkness(j2000: [m31, m7, m104], from: t.start, to: t.end, observer: chicago)
    let andromeda = try #require(best[0])
    #expect(andromeda.position.altitude > 85)
    #expect(andromeda.date > t.start && andromeda.date < t.end)
    // M7 peaks at about 13°, M104 is near the Sun.
    #expect(best[1] == nil)
    #expect(best[2] == nil)

    // M104 is 30° up at 13:00 CDT, but in daylight.
    let day = try SkyEngine.bestInDarkness(j2000: [m104], from: ut(18, 0), to: ut(20, 0), observer: chicago)
    #expect(day[0] == nil)
}
