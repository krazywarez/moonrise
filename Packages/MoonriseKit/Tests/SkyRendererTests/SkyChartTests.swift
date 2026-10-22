import Foundation
import Testing
import SkyEngine
@testable import SkyRenderer

@Test func horizonProfileInterpolatesAndStores() throws {
    var h = HorizonProfile()
    #expect(h.isFlat)
    h.altitudes[9] = 20  // 90°, east
    #expect(h.altitude(at: 90) == 20)
    #expect(h.altitude(at: 95) == 10)
    #expect(h.altitude(at: 85) == 10)
    #expect(h.altitude(at: 450) == 20)
    #expect(h.altitude(at: -270) == 20)
    #expect(HorizonProfile(stored: h.stored) == h)
    #expect(HorizonProfile(stored: "1,2") == nil)
}

@Test func faintStarsAroundAViewDirection() throws {
    #expect(Catalog.faintStars.count > 100_000)
    #expect(Catalog.faintStars.allSatisfy { $0.magnitude >= 5.95 && $0.magnitude <= 9.05 })
    let date = try Date("2026-08-15T23:00:00Z", strategy: .iso8601), here = Observer(latitude: 51.48, longitude: 0)
    let scene = try SkyScene(date: date, observer: here)
    // Vega (HR 7001): its horizontal position turned back to J2000 lands within a degree.
    let vega = try #require(scene.starsByHR[7001])
    let back = SkyEngine.approximateJ2000(of: vega, at: date, from: here)
    #expect(abs(back.ra - 279.23) < 1 && abs(back.dec - 38.78) < 1)
    let near = scene.faintStars(around: vega, radius: 5)
    #expect(near.count > 100 && near.count < 600)
    #expect(near.allSatisfy { $0.star.hr == 0 })
}
