import Foundation
import Testing
@testable import SkyEngine

/// Distance in km between two points on a sphere.
private func km(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> Double {
    let r = Double.pi / 180
    let h = pow(sin((b.lat - a.lat) * r / 2), 2) + cos(a.lat * r) * cos(b.lat * r) * pow(sin((b.lon - a.lon) * r / 2), 2)
    return 2 * 6371 * asin(h.squareRoot())
}

@Test func totalEclipse2027Path() throws {
    // NASA (Espenak): greatest eclipse 2027-08-02 10:07 UT at 25.5° N, 33.2° E,
    // totality 6 m 23 s, path 258 km wide; the path crosses southern Spain and Luxor.
    let path = try #require(EclipsePath.compute(near: Date(timeIntervalSince1970: 1_817_201_220)))
    #expect(path.kind == "Total")
    #expect(abs(path.greatest.lat - 25.5) < 0.3 && abs(path.greatest.lon - 33.2) < 0.3)
    let duration = try #require(path.centralDuration)
    #expect(abs(duration - 383) < 5)
    #expect(path.points.count > 100)

    func nearest(_ place: (lat: Double, lon: Double)) -> Double {
        path.points.map { km($0.center, place) }.min()!
    }
    #expect(nearest((25.69, 32.64)) < 40) // Luxor, close to the centre line
    #expect(nearest((36.01, -5.60)) < 120) // Tarifa, inside the path

    let middle = path.points.min { abs($0.date.timeIntervalSince(path.peak)) < abs($1.date.timeIntervalSince(path.peak)) }!
    #expect(abs(middle.widthKm - 258) < 20)
}

@Test func noPathForPartialEclipse() {
    // 21 September 2025 was partial only.
    #expect(EclipsePath.compute(near: Date(timeIntervalSince1970: 1_758_483_660)) == nil)
}

@Test func localCircumstances2027() throws {
    let peak = Date(timeIntervalSince1970: 1_817_201_220)
    let luxor = try #require(LocalEclipse.at(Observer(latitude: 25.69, longitude: 32.64), near: peak))
    #expect(luxor.kind == "Total")
    let begin = try #require(luxor.centralBegin), end = try #require(luxor.centralEnd)
    #expect(end.timeIntervalSince(begin) > 360)
    let madrid = try #require(LocalEclipse.at(Observer(latitude: 40.42, longitude: -3.70), near: peak))
    #expect(madrid.kind == "Partial" && madrid.centralBegin == nil)
    #expect(madrid.obscuration > 0.8 && madrid.obscuration < 0.95)
    #expect(LocalEclipse.at(Observer(latitude: 41.88, longitude: -87.63), near: peak) == nil) // Chicago: night
}

@Test func moonMatchesHorizonsFrame() {
    // Artemis I from JPL Horizons (geocentric, J2000 ecliptic, km) at 12:47 UTC on 21 November 2022,
    // ten minutes before its closest approach, about 130 km above the Moon.
    let craft = SIMD3<Double>(-337_632.7, -172_437.2, 9_689.0)
    let moon = SkyEngine.geocentricMoonEcliptic(at: Date(timeIntervalSince1970: 1_669_034_820))
    let d = ((craft - moon) * (craft - moon)).sum().squareRoot()
    #expect(d < 3_000)
}
