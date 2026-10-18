import Foundation
import Testing
@testable import Feeds

@Test func decodesLiveDSNSnapshot() throws {
    // dsn.xml saved from eyes.nasa.gov/dsn/data/dsn.xml on 2026-10-18.
    let url = try #require(Bundle.module.url(forResource: "Fixtures/dsn", withExtension: "xml"))
    let s = try DSNStatus.decode(Data(contentsOf: url))
    #expect(s.dishes.count == 15)
    #expect(Set(s.dishes.map(\.station)) == ["Goldstone", "Madrid", "Canberra"])
    #expect(s.updated > Date(timeIntervalSince1970: 1_790_000_000))
    #expect(s.dishes.first { $0.name == "DSS14" }?.activity == "Engineering Upgrades")
}

@Test func linksNeedAnActiveSignal() throws {
    let xml = Data("""
    <dsn><station name="gdscc" friendlyName="Goldstone" timeUTC="1792312582000"/>
    <dish name="DSS43" activity="Spacecraft Telemetry">
      <downSignal active="true" dataRate="160" band="X" spacecraft="VGR2" spacecraftID="-32"/>
      <upSignal active="false" spacecraft="VGR2" spacecraftID="-32"/>
      <downSignal active="false" spacecraft="MRO" spacecraftID="-74"/>
      <target name="VGR2" id="32" rtlt="138000"/>
    </dish></dsn>
    """.utf8)
    let s = try DSNStatus.decode(xml)
    let links = try #require(s.dishes.first?.links)
    #expect(links.count == 1)
    #expect(links[0].spacecraft == "Voyager 2")
    #expect(links[0].receiving && !links[0].sending)
    #expect(links[0].downlinkRate == 160)
    #expect(links[0].roundTrip == 138000)
}
