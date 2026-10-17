import Testing
import SkyEngine
@testable import SkyRenderer

// Rows of the rotation matrix are the device axes in reference coordinates
// (x north, y west, z up); the third row is the device z axis, toward the user.

@Test func uprightFacingNorth() {
    // Screen faces south, so device z = south = (-1, 0, 0).
    let h = Pointing.direction(m31: -1, m32: 0, m33: 0)
    #expect(abs(h.altitude) < 1e-9)
    #expect(abs(h.azimuth) < 1e-9)
}

@Test func uprightFacingEast() {
    // Screen faces west: device z = (0, 1, 0).
    let h = Pointing.direction(m31: 0, m32: 1, m33: 0)
    #expect(abs(h.azimuth - 90) < 1e-9)
}

@Test func flatFaceUpPointsDown() {
    let h = Pointing.direction(m31: 0, m32: 0, m33: 1)
    #expect(abs(h.altitude + 90) < 1e-9)
}

@Test func tiltedUpToward45DegreesSouth() {
    // Camera toward south and 45° up: −z = (−s, 0, s), so z = (s, 0, −s).
    let s = 0.5.squareRoot()
    let h = Pointing.direction(m31: s, m32: 0, m33: -s)
    #expect(abs(h.altitude - 45) < 1e-9)
    #expect(abs(h.azimuth - 180) < 1e-9)
}
