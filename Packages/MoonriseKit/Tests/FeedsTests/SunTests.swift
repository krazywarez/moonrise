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

@Test func kpBarsMarkPredicted() throws {
    let bars = try SpaceWeather.decodeKpBars(forecast)
    #expect(bars.count == 4)
    #expect(bars.first?.predicted == false)
    #expect(bars.last?.predicted == true)
}

@Test func solarImageURL() {
    #expect(SolarImage.corona.url().absoluteString == "https://sdo.gsfc.nasa.gov/assets/img/latest/latest_1024_0171.jpg")
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
