import Foundation
import Testing
@testable import SkyEngine

@Test func msdReferenceEpoch() {
    // Allison & McEwen (2000): MSD 44796.0 at about 2000-01-06 00:00 TT.
    let tt = Date(timeIntervalSince1970: 947_116_800 - 69.184)
    #expect(abs(MarsTime.msd(tt) - 44796.0) < 0.001)
}

@Test func landingDaysAreSolZero() throws {
    let perseverance = try #require(MarsTime.Rover.active.first { $0.name == "Perseverance" })
    let curiosity = try #require(MarsTime.Rover.active.first { $0.name == "Curiosity" })
    #expect(MarsTime.sol(utc("2021-02-18T20:55:00Z"), rover: perseverance) == 0)
    #expect(MarsTime.sol(utc("2012-08-06T05:17:57Z"), rover: curiosity) == 0)
    // One sol is 88,775.244 s.
    #expect(MarsTime.sol(utc("2021-02-18T20:55:00Z").addingTimeInterval(88_775.244), rover: perseverance) == 1)
}

@Test func localTimeIsWithinADay() {
    let t = MarsTime.localMeanTime(.now, eastLongitude: 77.45)
    #expect(t >= 0 && t < 24)
    #expect(MarsTime.format(hours: 13.5) == "13:30")
}
