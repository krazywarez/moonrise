import Foundation
import Testing
@testable import Feeds

@Test func flareClasses() {
    #expect(XRay.flareClass(1.5261429098245571e-06) == "C1.5")
    #expect(XRay.flareClass(6.587599727936322e-07) == "B6.6")
    #expect(XRay.flareClass(2.3e-4) == "X2.3")
    #expect(XRay.flareClass(4e-9) == "A0.4")
}

@Test func decodesLongChannelOnly() throws {
    // Shape copied from xrays-6-hour.json on 2026-10-17.
    let data = Data("""
    [{"time_tag": "2026-10-17T17:43:00Z", "satellite": 18, "flux": 1.195e-08, "observed_flux": 3.2e-08, "electron_correction": 2.0e-08, "electron_contaminaton": true, "energy": "0.05-0.4nm"},
     {"time_tag": "2026-10-17T17:43:00Z", "satellite": 18, "flux": 6.5876e-07, "observed_flux": 6.9e-07, "electron_correction": 3.1e-08, "electron_contaminaton": false, "energy": "0.1-0.8nm"},
     {"time_tag": "2026-10-17T17:44:00Z", "satellite": 18, "flux": null, "energy": "0.1-0.8nm"}]
    """.utf8)
    let samples = try XRay.decode(data)
    #expect(samples.count == 1)
    #expect(samples[0].flux == 6.5876e-07)
}

@Test func xrayMaximaKeepPeaks() throws {
    let start = try Date("2026-10-17T00:00:00Z", strategy: .iso8601)
    var samples = (0..<1440).map { XRaySample(time: start.addingTimeInterval(Double($0) * 60), flux: 1e-7 * (1 + Double($0 % 7) / 10)) }
    samples[733].flux = 2.4e-5  // one-minute M2.4 at 12:13
    samples[1001].flux = 3.1e-6  // C3.1 at 16:41
    let m = XRay.maxima(samples)
    #expect(m.count == 288)
    #expect(m.contains(samples[733]))
    #expect(m.contains(samples[1001]))
    #expect(m.max { $0.flux < $1.flux } == samples[733])
    for (i, s) in m.enumerated() {
        #expect(s.flux == samples[i * 5..<i * 5 + 5].map(\.flux).max())
    }
}

@Test func kpBarsMarkPredicted() throws {
    let bars = try SpaceWeather.decodeKpBars(forecast)
    #expect(bars.count == 4)
    #expect(bars.first?.predicted == false)
    #expect(bars.last?.predicted == true)
}

@Test func solarImageURL() {
    #expect(SolarImage.corona.url().absoluteString == "https://sdo.gsfc.nasa.gov/assets/img/latest/latest_1024_0171.jpg")
}

/// SDO frames from 2026-10-21, downscaled to 256 px.
@Test(arguments: [
    ("sdo-0171", SolarImage.corona, true),
    ("sdo-HMIIC", .visible, true),
    ("sdo-0193-black", .hotCorona, false),
    ("sdo-0304-black", .chromosphere, false),
    ("sdo-0193-covered-151634", .hotCorona, false),
    ("sdo-0193-covered-163614", .hotCorona, false),
])
func solarFrameUsable(name: String, image: SolarImage, usable: Bool) throws {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jpg"))
    #expect(image.isUsable(try Data(contentsOf: url)) == usable)
}

@Test func solarFrameUsableRejectsNonImages() {
    #expect(!SolarImage.corona.isUsable(Data("<html></html>".utf8)))
}

@Test func solarArchiveListing() throws {
    let day = try Date("2026-10-21T17:00:00Z", strategy: .iso8601)
    let listing = SolarImage.hotCorona.archiveURL(day: day)
    #expect(listing.absoluteString == "https://sdo.gsfc.nasa.gov/assets/img/browse/2026/10/21/?P=*_1024_0193.jpg")
    // Lines from the listing on 2026-10-21.
    let html = """
    <img src="/icons/back.gif" alt="[PARENTDIR]"> <a href="/assets/img/browse/2026/10/">Parent Directory</a>                                          -
    <img src="/icons/image2.gif" alt="[IMG]"> <a href="20261021_000653_1024_0193.jpg">20261021_000653_1024_0193.jpg</a>        2026-10-20 19:13  138K
    <img src="/icons/image2.gif" alt="[IMG]"> <a href="20261021_000653_512_0193.jpg">20261021_000653_512_0193.jpg</a>         2026-10-20 19:13   45K
    <img src="/icons/image2.gif" alt="[IMG]"> <a href="20261021_000658_1024_0171.jpg">20261021_000658_1024_0171.jpg</a>        2026-10-20 19:12  182K
    <img src="/icons/image2.gif" alt="[IMG]"> <a href="20261021_162634_1024_0193.jpg">20261021_162634_1024_0193.jpg</a>        2026-10-21 11:33   90K
    <img src="/icons/image2.gif" alt="[IMG]"> <a href="20261021_172654_1024_0193.jpg">20261021_172654_1024_0193.jpg</a>        2026-10-21 12:33  134K
    """
    let frames = SolarImage.hotCorona.frames(inListing: html, at: listing)
    #expect(frames.map(\.url.absoluteString) == [
        "https://sdo.gsfc.nasa.gov/assets/img/browse/2026/10/21/20261021_172654_1024_0193.jpg",
        "https://sdo.gsfc.nasa.gov/assets/img/browse/2026/10/21/20261021_162634_1024_0193.jpg",
        "https://sdo.gsfc.nasa.gov/assets/img/browse/2026/10/21/20261021_000653_1024_0193.jpg",
    ])
    #expect(frames[1].time == (try Date("2026-10-21T16:26:34Z", strategy: .iso8601)))
    #expect(SolarImage.hotCorona.frames(inListing: "<html>Not Found</html>", at: listing).isEmpty)
}

@Test func ovationKeepsNonZeroCells() throws {
    // Shape from ovation_aurora_latest.json on 2026-10-17.
    let data = Data("""
    {"Observation Time": "2026-10-17T23:38:00Z", "Forecast Time": "2026-10-18T00:37:00Z", "Data Format": "[Longitude, Latitude, Aurora]",
     "coordinates": [[0, -90, 3], [0, -89, 0], [0, 65, 12]], "type": "MultiPoint"}
    """.utf8)
    let o = try Ovation.decode(data)
    #expect(o.cells.count == 2)
    #expect(o.cells.last == Ovation.Cell(lon: 0, lat: 65, probability: 12))
    #expect(o.forecastTime == (try Date("2026-10-18T00:37:00Z", strategy: .iso8601)))
}

@Test func ovationSavesAsGrid() throws {
    let rows = (0..<360).flatMap { lon in (-90...90).map { lat in "[\(lon),\(lat),\(abs(lat) >= 55 && abs(lat) <= 80 ? (lon + lat + 90) % 101 : 0)]" } }
    let feed = Data(#"{"Forecast Time": "2026-10-18T00:37:00Z", "coordinates": [\#(rows.joined(separator: ","))]}"#.utf8)
    let o = try Ovation.decode(feed)
    let data = try JSONEncoder().encode(o)
    #expect(data.count < 20_000)
    #expect(try JSONDecoder().decode(Ovation.self, from: data) == o)
}

@Test func ovationReadsUncompressedGridFromOlderSnapshots() throws {
    var grid = Data(count: 360 * 181)
    grid[0 * 181 + 155] = 12
    grid[359 * 181 + 30] = 3
    let data = Data(#"{"forecastTime": 782614800, "grid": "\#(grid.base64EncodedString())"}"#.utf8)
    let o = try JSONDecoder().decode(Ovation.self, from: data)
    #expect(o.cells == [Ovation.Cell(lon: 0, lat: 65, probability: 12), Ovation.Cell(lon: 359, lat: -60, probability: 3)])
}

@Test func ovationReadsCellsFromOlderSnapshots() throws {
    let data = Data(#"{"forecastTime": 782614800, "cells": [{"lon": 0, "lat": 65, "probability": 12}, {"lon": 359, "lat": -60, "probability": 3}]}"#.utf8)
    let o = try JSONDecoder().decode(Ovation.self, from: data)
    #expect(o.cells == [Ovation.Cell(lon: 0, lat: 65, probability: 12), Ovation.Cell(lon: 359, lat: -60, probability: 3)])
}

@Test func solarB0FollowsTheYear() {
    // B0 is about 0° in early June and December, +7.25° in early September, −7.25° in early March.
    let at = { (s: String) in SolarRegion.b0(at: try! Date(s, strategy: .iso8601)) }
    #expect(abs(at("2026-06-06T00:00:00Z")) < 0.5)
    #expect(abs(at("2026-09-07T00:00:00Z") - 7.25) < 0.3)
    #expect(abs(at("2026-03-06T00:00:00Z") + 7.25) < 0.3)
}

@Test func regionsRotateWestAndLeaveTheDisk() throws {
    let data = Data(#"[{"region":4560,"observed_date":"2026-10-21","latitude":13,"longitude":-28,"area":150},{"region":4551,"observed_date":"2026-10-21","latitude":-16,"longitude":-85,"area":340},{"region":4500,"observed_date":"2026-10-20","latitude":0,"longitude":0,"area":10}]"#.utf8)
    let regions = try SolarRegion.decode(data)
    #expect(regions.map(\.number) == [4560, 4551])
    let r = regions[0], noon = try Date("2026-10-22T12:00:00Z", strategy: .iso8601)
    let p = try #require(r.disk(at: noon))
    #expect(p.x > sin(28 * Double.pi / 180) * 0.9)
    #expect(p.y > 0)
    #expect(regions[1].disk(at: try Date("2026-10-23T12:00:00Z", strategy: .iso8601)) == nil)
}
