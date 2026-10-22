import Foundation
import Testing
@testable import SkyEngine

private let greenwich = Observer(latitude: 51.4779, longitude: -0.0015)

@Test func sunDayAtGreenwichInSummerAndWinter() throws {
    let june = try SunDay(start: try Date("2026-06-21T00:00:00Z", strategy: .iso8601), observer: greenwich)
    let summer: TimeInterval = 16 * 3600 + 38 * 60, winter: TimeInterval = 7 * 3600 + 50 * 60
    let juneLength = try #require(june.dayLength)
    #expect(abs(juneLength - summer) < 300)
    #expect(abs(try #require(june.noonAltitude) - 62) < 0.5)
    let golden = try #require(june.eveningGolden), blue = try #require(june.eveningBlue)
    #expect(golden.end == blue.start)
    #expect(try #require(june.sunset) > golden.start && june.sunset! < golden.end)
    let december = try SunDay(start: try Date("2026-12-21T00:00:00Z", strategy: .iso8601), observer: greenwich)
    let decemberLength = try #require(december.dayLength)
    #expect(abs(decemberLength - winter) < 300)
    #expect(june.path.count == 145)
}

@Test func polarNightHasNoSunrise() throws {
    let svalbard = Observer(latitude: 78.22, longitude: 15.65)
    let d = try SunDay(start: try Date("2026-12-21T00:00:00Z", strategy: .iso8601), observer: svalbard)
    #expect(d.sunrise == nil && d.sunset == nil && d.dayLength == nil)
    #expect(d.morningGolden == nil && d.eveningGolden == nil)
    #expect(d.path.allSatisfy { $0.altitude < 0 })
}
