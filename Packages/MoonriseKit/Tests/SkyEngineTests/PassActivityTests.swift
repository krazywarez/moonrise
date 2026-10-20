import Foundation
import Testing
@testable import SkyEngine

private let now = Date(timeIntervalSince1970: 1_792_364_400)

private func pass(risingIn seconds: TimeInterval) -> SatellitePass {
    SatellitePass(name: "ISS (ZARYA)", rise: now.addingTimeInterval(seconds), set: now.addingTimeInterval(seconds + 360), peak: now.addingTimeInterval(seconds + 180),
                  maxAltitude: 62, riseAzimuth: 240, setAzimuth: 60, visible: true, featured: true)
}

@Test func activityStartsTenMinutesBeforeRise() {
    #expect(pass(risingIn: 3600).activityStart(now: now) == now.addingTimeInterval(3000))
    #expect(pass(risingIn: 24 * 3600).activityStart(now: now) == now.addingTimeInterval(24 * 3600 - 600))
}

@Test func activityStartsNowWithinTenMinutesOrDuringThePass() {
    #expect(pass(risingIn: 300).activityStart(now: now) == now)
    #expect(pass(risingIn: -120).activityStart(now: now) == now)
}

@Test func noActivityAfterSetOrBeyondADay() {
    #expect(pass(risingIn: -360).activityStart(now: now) == nil)
    #expect(pass(risingIn: 24 * 3600 + 1).activityStart(now: now) == nil)
}

@Test func compassPoints() {
    #expect(SkyEngine.compass(0) == "N")
    #expect(SkyEngine.compass(22.4) == "N")
    #expect(SkyEngine.compass(22.5) == "NE")
    #expect(SkyEngine.compass(240) == "SW")
    #expect(SkyEngine.compass(359) == "N")
}
