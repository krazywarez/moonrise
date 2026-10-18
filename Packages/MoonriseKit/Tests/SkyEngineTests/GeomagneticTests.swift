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
