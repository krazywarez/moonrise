import Foundation
import Testing
@testable import SkyEngine

private let summaryObserver = Observer(latitude: 41.878, longitude: -87.630)
private let central = TimeZone(identifier: "America/Chicago")!
private let gb = Locale(identifier: "en_GB")

@Test func phaseNames() {
    #expect(DailySummary.phaseName(3) == "New moon")
    #expect(DailySummary.phaseName(45) == "Waxing crescent")
    #expect(DailySummary.phaseName(90) == "First quarter")
    #expect(DailySummary.phaseName(180) == "Full moon")
    #expect(DailySummary.phaseName(271) == "Last quarter")
    #expect(DailySummary.phaseName(320) == "Waning crescent")
}

@Test func summaryForAnEvening() throws {
    // 18:00 CDT, 18 October 2026.
    let date = Date(timeIntervalSince1970: 1_792_364_400)
    let pass = SatellitePass(name: "ISS (ZARYA)", rise: date.addingTimeInterval(5400), set: date.addingTimeInterval(5760), peak: date.addingTimeInterval(5580), maxAltitude: 54.4, riseAzimuth: 240, setAzimuth: 60, visible: true)
    let faint = SatellitePass(name: "HST", rise: date.addingTimeInterval(7200), set: date.addingTimeInterval(7500), peak: date.addingTimeInterval(7350), maxAltitude: 70, riseAzimuth: 200, setAzimuth: 80, visible: false)
    let event = SkyEvent(kind: .meteorShower, date: date.addingTimeInterval(3 * 3600), title: "Orionids peak", detail: "", visibleHere: nil)
    let tomorrow = SkyEvent(kind: .moonPhase, date: date.addingTimeInterval(30 * 3600), title: "Full moon", detail: "", visibleHere: nil)

    let s = try DailySummary.make(at: date, observer: summaryObserver, passes: [pass, faint], events: [event, tomorrow], locale: gb, timeZone: central)
    #expect(s.title.hasPrefix("Tonight: "))
    #expect(s.title.hasSuffix("% lit"))
    #expect(s.body.hasPrefix("Orionids peak. "))
    #expect(!s.body.contains("Full moon"))
    #expect(s.body.contains("Up tonight: "))
    #expect(s.body.contains("ISS (ZARYA) passes at 19:30, 54° high."))
    #expect(!s.body.contains("HST"))
    #expect(s.body.contains("Sunset 18:"))
}

@Test func morningPassSaysTomorrow() throws {
    let date = Date(timeIntervalSince1970: 1_792_364_400)
    // 05:37 CDT on 19 October, before dawn.
    let pass = SatellitePass(name: "ISS (ZARYA)", rise: date.addingTimeInterval(41_820), set: date.addingTimeInterval(42_180), peak: date.addingTimeInterval(42_000), maxAltitude: 40, riseAzimuth: 240, setAzimuth: 60, visible: true)
    let s = try DailySummary.make(at: date, observer: summaryObserver, passes: [pass], events: [], locale: gb, timeZone: central)
    #expect(s.body.contains("ISS (ZARYA) passes at 5:37 tomorrow, 40° high."))
}
