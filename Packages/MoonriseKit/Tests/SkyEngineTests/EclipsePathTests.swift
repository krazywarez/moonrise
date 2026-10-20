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

/// Contacts for 2 August 2027 from NASA's local circumstances calculator for this eclipse (Espenak and Jubier, SEcirc.js on
/// eclipse.gsfc.nasa.gov/SEgoogle/SEgoogle2001/SE2027Aug02Tgoogle.html, VSOP87/ELP2000-85 Besselian elements), run with
/// ΔT = 69.38 s instead of the page's 71.7 s. UT seconds after midnight: C1, C2, C3, C4.
private let nasa2027: [(name: String, lat: Double, lon: Double, contacts: [Double])] = [
    ("Tarifa", 36.0143, -5.6044, [27_652.7, 31_508.2, 31_786.9, 36_044.7]), // 07:40:52.7, 08:45:08.2, 08:49:46.9, 10:00:44.7
    ("Tangier", 35.7595, -5.8340, [27_635.1, 31_481.1, 31_771.6, 36_023.0]), // 07:40:35.1, 08:44:41.1, 08:49:31.6, 10:00:23.0
    ("Luxor", 25.6872, 32.6396, [31_216.4, 36_126.7, 36_507.1, 41_193.5]), // 08:40:16.4, 10:02:06.7, 10:08:27.1, 11:26:33.5
]

@Test(arguments: nasa2027.indices) func contactsMatchNASA2027(_ i: Int) throws {
    let site = nasa2027[i]
    let midnight = Date(timeIntervalSince1970: 1_817_164_800)
    let l = try #require(LocalEclipse.at(Observer(latitude: site.lat, longitude: site.lon), near: midnight.addingTimeInterval(36_000)))
    let c2 = try #require(l.centralBegin), c3 = try #require(l.centralEnd)
    let ours = [l.partialBegin, c2, c3, l.partialEnd].map { $0.timeIntervalSince(midnight) }
    for (a, b) in zip(ours, site.contacts) { #expect(abs(a - b) < 3, "\(site.name)") }
    #expect(abs((ours[2] - ours[1]) - (site.contacts[2] - site.contacts[1])) < 3, "\(site.name) duration")
}

@Test func contactsRefinedToATenthOfASecond() throws {
    let tarifa = Observer(latitude: 36.0143, longitude: -5.6044)
    let l = try #require(LocalEclipse.at(tarifa, near: Date(timeIntervalSince1970: 1_817_201_220)))
    let inner = { (s: LocalEclipse.Shadow) in abs(s.k) - s.r }, partial = { (s: LocalEclipse.Shadow) in s.p - s.r }
    for (contact, edge) in [(l.partialBegin, partial), (try #require(l.centralBegin), inner), (try #require(l.centralEnd), inner), (l.partialEnd, partial)] {
        let before = edge(LocalEclipse.shadow(at: contact.addingTimeInterval(-0.05), from: tarifa))
        let after = edge(LocalEclipse.shadow(at: contact.addingTimeInterval(0.05), from: tarifa))
        #expect(before * after < 0)
    }
}

@Test func moonMatchesHorizonsFrame() {
    // Artemis I from JPL Horizons (geocentric, J2000 ecliptic, km) at 12:47 UTC on 21 November 2022,
    // ten minutes before its closest approach, about 130 km above the Moon.
    let craft = SIMD3<Double>(-337_632.7, -172_437.2, 9_689.0)
    let moon = SkyEngine.geocentricMoonEcliptic(at: Date(timeIntervalSince1970: 1_669_034_820))
    let d = ((craft - moon) * (craft - moon)).sum().squareRoot()
    #expect(d < 3_000)
}
