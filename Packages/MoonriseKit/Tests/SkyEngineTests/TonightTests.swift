import Foundation
import Testing
@testable import SkyEngine

@Test func tonightFromDarkStartsNowAndEndsAtSunrise() throws {
    // 2026-10-17 02:00 UT is 21:00 CDT on the 16th: already dark in Chicago.
    let t = try Tonight(at: observed, from: chicago)
    #expect(t.start == observed)
    #expect(t.sunset == nil)
    let sunrise = try #require(t.sunrise)
    #expect(abs(sunrise.timeIntervalSince(ut(12, 6))) < 120)
    let saturn = try #require(t.planets.first { $0.body == .saturn })
    #expect(saturn.best != nil)
    #expect(t.planets.first?.best != nil)
}

@Test func tonightFromAfternoonStartsAtSunset() throws {
    // 2026-10-17 18:00 UT is 13:00 CDT.
    let afternoon = ut(18, 0)
    let t = try Tonight(at: afternoon, from: chicago)
    let sunset = try #require(t.sunset)
    #expect(abs(sunset.timeIntervalSince(ut(23, 6))) < 120)
    #expect(t.start == sunset)
}

@Test func visiblePlanetsMatchTonightAtEachDate() throws {
    let places = [chicago, Observer(latitude: -0.18, longitude: -78.47), Observer(latitude: -33.87, longitude: 151.21), Observer(latitude: 69.65, longitude: 18.96)]
    let days = try ["2026-01-15", "2026-03-20", "2026-05-14", "2026-06-21", "2026-10-17", "2026-12-21"].map { try Date($0 + "T00:00:00Z", strategy: .iso8601) }
    for observer in places {
        for day in days {
            for hour in [0.0, 6, 12, 18] {
                let dates = (0..<12).map { day.addingTimeInterval(hour * 3600 + 433.25 + Double($0) * 3600) }
                let got = try Tonight.visiblePlanets(at: dates, from: observer)
                for (date, g) in zip(dates, got) {
                    let t = try Tonight(at: date, from: observer)
                    let want = t.planets.filter { $0.best != nil }
                    #expect(g.end == t.end)
                    #expect(g.planets.map(\.body) == want.map(\.body), "\(observer) \(date)")
                    for (a, b) in zip(g.planets, want) {
                        #expect(a.magnitude == b.magnitude && a.now == b.now && a.rise == b.rise && a.set == b.set)
                        #expect(abs(a.best!.date.timeIntervalSince(b.best!.date)) < 1)
                    }
                }
            }
        }
    }
}
