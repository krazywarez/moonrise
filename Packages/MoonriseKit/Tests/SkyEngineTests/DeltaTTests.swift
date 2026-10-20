import Foundation
import Testing
@testable import SkyEngine

private func ut(_ year: Double) -> Double { (year - 2000) * 365.24217 + 14 }

@Test func deltaTFollowsIERS() {
    // IERS Bulletin A, 15 October 2026: UT1 − UTC = −0.0367 s that day and −0.198 s predicted for 2 August 2027.
    let now = SkyEngine.time(Date(timeIntervalSince1970: 1_792_022_400))
    #expect(abs((now.tt - now.ut) * 86_400 - 69.221) < 0.01)
    let eclipse = SkyEngine.time(Date(timeIntervalSince1970: 1_817_201_220))
    #expect(abs((eclipse.tt - eclipse.ut) * 86_400 - 69.382) < 0.01)
}

@Test func deltaTUnchangedOutsideModernEra() {
    for year in [-3000.0, -500, 1000, 1700, 1900, 2000, 2010, 2050, 2100, 3000] {
        #expect(DeltaT.seconds(ut: ut(year)) == DeltaT.polynomial(year))
    }
}

@Test func deltaTHasNoSteps() {
    var previous = DeltaT.seconds(ut: ut(2005))
    for month in 1...(12 * 50) {
        let next = DeltaT.seconds(ut: ut(2005 + Double(month) / 12))
        #expect(abs(next - previous) < 0.25)
        previous = next
    }
}
