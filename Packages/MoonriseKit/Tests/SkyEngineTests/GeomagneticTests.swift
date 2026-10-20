import Testing
@testable import SkyEngine

@Test func chicagoIsAboutFiftyOneDegreesGeomagnetic() {
    let m = Geomagnetic.latitude(chicago)
    #expect(m > 49 && m < 53, "\(m)")
    #expect(Geomagnetic.band(chicago) == 50)
}

@Test func southernBandsAreNegative() {
    // Hobart, Tasmania: the dipole model gives about 49.6° S, so the 45–50° S band.
    let hobart = Observer(latitude: -42.88, longitude: 147.33)
    let m = Geomagnetic.latitude(hobart)
    #expect(m < -45 && m > -55, "\(m)")
    #expect(Geomagnetic.band(hobart) == -50)
}

@Test func poleIsNinety() {
    let pole = Observer(latitude: Geomagnetic.poleLatitude, longitude: Geomagnetic.poleLongitude)
    #expect(abs(Geomagnetic.latitude(pole) - 90) < 1e-6)
}

@Test func ovalMatchesServer() {
    // server/src/aurora.ts: ovalEdge(5) = 56.3, visibleFrom(5) = 50.3.
    #expect(abs(Geomagnetic.ovalEdge(kp: 5) - 56.3) < 1e-9)
    #expect(abs(Geomagnetic.visibleFrom(kp: 5) - 50.3) < 1e-9)
}

@Test func kpNeeded() {
    let kp = Geomagnetic.kpNeeded(chicago)
    #expect(kp > 4 && kp < 5.5, "\(kp)")
    #expect(abs(Geomagnetic.visibleFrom(kp: kp) - Geomagnetic.latitude(chicago)) < 1e-9)
    #expect(Geomagnetic.kpNeeded(Observer(latitude: -42.88, longitude: 147.33)) < 6)
    #expect(Geomagnetic.kpNeeded(Observer(latitude: 0, longitude: -80)) > 9)
    #expect(Geomagnetic.kpNeeded(Observer(latitude: 69.6, longitude: 18.9)) == 0)
}
