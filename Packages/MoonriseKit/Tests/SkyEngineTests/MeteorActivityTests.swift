import Foundation
import Testing
@testable import SkyEngine

private let now = Date(timeIntervalSince1970: 1_792_364_400)

private func peak(darkIn seconds: TimeInterval, kind: SkyEvent.Kind = .meteorShower) -> SkyEvent {
    SkyEvent(kind: kind, date: now, title: "Orionids peak", detail: "", visibleHere: nil,
             window: DateInterval(start: now.addingTimeInterval(seconds), duration: 8 * 3600), zhr: 20, moonIllumination: 0.1)
}

@Test func meteorActivityStartsTenMinutesBeforeDark() {
    #expect(peak(darkIn: 3600).activityStart(now: now) == now.addingTimeInterval(3000))
    #expect(peak(darkIn: 300).activityStart(now: now) == now)
    #expect(peak(darkIn: -3600).activityStart(now: now) == now)
}

@Test func noMeteorActivityAfterTheNightBeyondADayOrForOtherEvents() {
    #expect(peak(darkIn: -8 * 3600).activityStart(now: now) == nil)
    #expect(peak(darkIn: 86_401).activityStart(now: now) == nil)
    #expect(peak(darkIn: 3600, kind: .opposition).activityStart(now: now) == nil)
}

@Test func meteorPeaksCarryRateAndMoon() throws {
    let e = try #require(SkyEngine.events(from: now, observer: Observer(latitude: 41.88, longitude: -87.63)).first { $0.kind == .meteorShower })
    #expect(e.zhr != nil)
    #expect((0...1).contains(try #require(e.moonIllumination)))
}
