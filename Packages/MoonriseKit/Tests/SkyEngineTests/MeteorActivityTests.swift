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

@Test func radiantAltitudeFollowsTheSky() throws {
    let chicago = Observer(latitude: 41.88, longitude: -87.63)
    let perseids = try #require(MeteorShower.major.first { $0.name == "Perseids" })
    // 2026-08-13 03:00–09:00 UTC, the dark hours over Chicago: the radiant climbs all night and peaks near dawn.
    let night = DateInterval(start: Date(timeIntervalSince1970: 1_786_590_000), duration: 6 * 3600)
    let best = perseids.highestRadiant(in: night, from: chicago)
    #expect(best.date > night.start.addingTimeInterval(5 * 3600))
    #expect((60...80).contains(best.altitude))
    // From Sydney the Ursids (dec +75) never rise.
    let ursids = try #require(MeteorShower.major.first { $0.name == "Ursids" })
    let sydney = Observer(latitude: -33.87, longitude: 151.21)
    #expect(ursids.radiantNote(in: night, from: sydney) == "The radiant stays below the horizon while it is dark.")
}
