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

@Test func pinholeProjectionFacingNorth() {
    // Upright in portrait, facing north: x (right) is east, y (up) is up, z (towards the user) is south.
    let pose = CameraPose(rows: (SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(-1, 0, 0)), focal: 500)
    let p = Projection(centerAzimuth: 0, centerAltitude: 0, fieldOfView: 60, size: CGSize(width: 400, height: 800), camera: pose)
    let north = p.point(Horizontal(altitude: 0, azimuth: 0))!
    #expect(abs(north.x - 200) < 1e-9)
    #expect(abs(north.y - (400 - 500 * tan(CameraPose.refraction(0) * .pi / 180))) < 1e-6)
    let up = p.point(Horizontal(altitude: 10, azimuth: 0))!
    #expect(up.y < north.y && abs(up.x - 200) < 1e-9)
    let east = p.point(Horizontal(altitude: 0, azimuth: 10))!
    #expect(east.x > 200)
    #expect(p.point(Horizontal(altitude: 0, azimuth: 180)) == nil)
    #expect(abs(CameraPose.refraction(0) - 0.48) < 0.03)
    #expect(abs(CameraPose.refraction(45) * 60 - 1.0) < 0.1)
}
