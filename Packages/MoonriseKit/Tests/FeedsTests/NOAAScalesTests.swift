import Foundation
import Testing
@testable import Feeds

// Fixtures saved from the live SWPC feeds on 2026-10-19.

@Test func decodesCurrentAndPastDayScales() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/noaa-scales", withExtension: "json"))
    let s = try NOAAScales.decode(Data(contentsOf: url))
    #expect(s.current == NOAAScales.Levels(r: 0, s: 0, g: 0))
    #expect(s.past24h == NOAAScales.Levels(r: 1, s: 0, g: 0))
    #expect(s.asOf == (try Date("2026-10-19T21:13:00Z", strategy: .iso8601)))
}

@Test func scaleLevelNames() {
    #expect(NOAAScales.levelName(0) == "none")
    #expect(NOAAScales.levelName(3) == "strong")
    #expect(NOAAScales.levelName(5) == "extreme")
}

@Test func decodesNewestProbabilities() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/solar-probabilities", withExtension: "json"))
    let p = try SolarProbabilities.decode(Data(contentsOf: url))
    #expect(p.issued == (try Date("2026-10-19T00:00:00Z", strategy: .iso8601)))
    #expect(p.days.count == 3)
    #expect(p.days[0] == SolarProbabilities.Day(c: 85, m: 25, x: 5, proton: 5))
}

@Test func probabilitiesForADate() throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/solar-probabilities", withExtension: "json"))
    let p = try SolarProbabilities.decode(Data(contentsOf: url))
    let issued = p.issued
    #expect(p.day(at: issued.addingTimeInterval(23 * 3600)) == p.days[0])
    #expect(p.day(at: issued.addingTimeInterval(25 * 3600)) == p.days[1])
    #expect(p.day(at: issued.addingTimeInterval(-3600)) == nil)
    #expect(p.day(at: issued.addingTimeInterval(73 * 3600)) == nil)
}

@Test func snapshotRoundTripsThroughDisk() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "sun-\(UUID().uuidString)/SunSnapshot.json")
    let snapshot = SunSnapshot(
        fetched: Date(timeIntervalSince1970: 1_800_000_000),
        kp: [KpBar(start: Date(timeIntervalSince1970: 1_800_000_000), kp: 5.33, predicted: true)],
        xray: [XRaySample(time: Date(timeIntervalSince1970: 1_800_000_060), flux: 2.4e-5)],
        ovation: Ovation(forecastTime: Date(timeIntervalSince1970: 1_800_000_000), cells: [.init(lon: 0, lat: 65, probability: 12)]),
        scales: NOAAScales(asOf: Date(timeIntervalSince1970: 1_800_000_000), current: .init(r: 1, s: 0, g: 2), past24h: .init(r: 2, s: 0, g: 2)),
        probabilities: SolarProbabilities(issued: Date(timeIntervalSince1970: 1_799_971_200), days: [.init(c: 85, m: 25, x: 5, proton: 5)])
    )
    try snapshot.save(to: file)
    #expect(SunSnapshot.load(from: file) == snapshot)
    #expect(SunSnapshot.load(from: file.deletingLastPathComponent().appending(path: "missing.json")) == nil)
}
