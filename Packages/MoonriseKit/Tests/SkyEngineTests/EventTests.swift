import Foundation
import Testing
@testable import SkyEngine

// Rise and set times from JPL Horizons (R_T_S_ONLY=TVH, refracted, minute resolution),
// Chicago, searching 2026-10-17 00:00 to 2026-10-18 00:00 UT.

let midnightUT = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17T00:00:00Z

func ut(_ hour: Int, _ minute: Int) -> Date {
    midnightUT.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
}

@Test(arguments: [
    (Body.sun, ut(12, 6), ut(23, 6)),
    (Body.saturn, ut(22, 39), ut(10, 58)),
    (Body.moon, ut(18, 57), ut(2, 49)),
])
func riseSetMatchesHorizons(_ body: Body, _ rise: Date, _ set: Date) throws {
    let r = SkyEngine.riseSet(body, after: midnightUT, from: chicago)
    let gotRise = try #require(r.rise)
    let gotSet = try #require(r.set)
    #expect(abs(gotRise.timeIntervalSince(rise)) < 120, "\(body) rise \(gotRise)")
    #expect(abs(gotSet.timeIntervalSince(set)) < 120, "\(body) set \(gotSet)")
}

@Test func nextQuarterAfterObservationIsFirstQuarter() throws {
    let q = try SkyEngine.nextMoonQuarter(after: observed)
    #expect(q.quarter == .firstQuarter)
    #expect(q.date > observed && q.date < observed.addingTimeInterval(4 * 86_400))
}
