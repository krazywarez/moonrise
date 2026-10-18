import Foundation
import Testing
@testable import SkyEngine

func utc(_ s: String) -> Date { try! Date(s, strategy: .iso8601) }

@Test func august2027TotalEclipseIsTotalFromLuxor() throws {
    let luxor = Observer(latitude: 25.69, longitude: 32.64)
    let events = SkyEngine.events(from: utc("2027-07-01T00:00:00Z"), days: 60, observer: luxor)
    let eclipse = try #require(events.first { $0.kind == .solarEclipse })
    #expect(eclipse.title == "Total solar eclipse")
    #expect(abs(eclipse.date.timeIntervalSince(utc("2027-08-02T10:07:00Z"))) < 3600)
    #expect(eclipse.visibleHere == true)
    #expect(eclipse.detail.contains("100%"))
}

@Test func august2026EclipseIsPartialFromChicagoOrNotVisible() throws {
    let events = SkyEngine.events(from: utc("2026-08-01T00:00:00Z"), days: 30, observer: chicago)
    let eclipse = try #require(events.first { $0.kind == .solarEclipse })
    #expect(eclipse.title == "Total solar eclipse")
    #expect(abs(eclipse.date.timeIntervalSince(utc("2026-08-12T17:46:00Z"))) < 3600)
}

@Test func saturnOpposition2026() throws {
    let events = SkyEngine.events(from: utc("2026-09-01T00:00:00Z"), days: 60, observer: chicago)
    let opp = try #require(events.first { $0.title == "Saturn at opposition" })
    #expect(abs(opp.date.timeIntervalSince(utc("2026-10-04T12:00:00Z"))) < 2 * 86_400)
}

@Test func yearOfEventsIsSortedAndHasEachKind() {
    let events = SkyEngine.events(from: utc("2026-10-18T00:00:00Z"), observer: chicago)
    #expect(events == events.sorted { $0.date < $1.date })
    let kinds = Set(events.map(\.kind))
    #expect(kinds.isSuperset(of: [.moonPhase, .lunarEclipse, .solarEclipse, .opposition, .elongation, .season, .meteorShower]))
}
