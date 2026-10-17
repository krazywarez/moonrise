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
