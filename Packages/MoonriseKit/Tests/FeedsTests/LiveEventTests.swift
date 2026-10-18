import Foundation
import Testing
@testable import Feeds

@Test func decodesLiveCoverage() throws {
    let json = Data("""
    {"event":{"id":"artemis-1","title":"Artemis I","horizonsId":"-1023","launch":"2022-11-16T06:47:44Z","end":"2022-12-11T17:40:00Z",
      "phases":[{"at":"2022-11-16T06:47:44Z","label":"Launch"},{"at":"2022-11-21T12:44:00Z","label":"Outbound lunar flyby"}]},
     "at":"2022-11-21T12:00:00.000Z","points":[[1668588420,-3171.3,10537.8,1526.1],[1669031220,300000,200000,10000]]}
    """.utf8)
    let c = try #require(try LiveCoverage.decode(json))
    #expect(c.event.title == "Artemis I")
    #expect(c.points.count == 2)
    #expect(c.phase.current?.label == "Launch")
    #expect(c.phase.next?.label == "Outbound lunar flyby")
    #expect(abs(c.distanceKm! - (300000.0 * 300000 + 200000 * 200000 + 10000 * 10000).squareRoot()) < 1e-6)
    #expect(try LiveCoverage.decode(Data(#"{"event":null}"#.utf8)) == nil)
}

@Test func decodesLiveArtemisReplay() throws {
    // GET /v1/live?at=2022-11-21T13:00:00Z, saved 2026-10-18.
    let url = try #require(Bundle.module.url(forResource: "Fixtures/live-artemis1", withExtension: "json"))
    let c = try #require(try LiveCoverage.decode(Data(contentsOf: url)))
    #expect(c.points.count > 200)
    #expect(c.phase.current?.label == "Outbound lunar flyby")
}
