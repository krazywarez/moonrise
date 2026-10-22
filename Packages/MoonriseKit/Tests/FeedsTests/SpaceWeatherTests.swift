import Foundation
import Testing
@testable import Feeds

// Shapes copied from the live SWPC feeds on 2026-10-17.
let minutes = Data("""
[{"time_tag": "2026-10-17T23:32:00", "kp_index": 0, "estimated_kp": 0.33, "kp": "0P"},
 {"time_tag": "2026-10-17T23:33:00", "kp_index": 0, "estimated_kp": 0.67, "kp": "1M"}]
""".utf8)

let forecast = Data("""
[{"time_tag": "2026-10-17T18:00:00", "kp": 2.33, "observed": "observed", "noaa_scale": null},
 {"time_tag": "2026-10-18T00:00:00", "kp": 3.67, "observed": "predicted", "noaa_scale": null},
 {"time_tag": "2026-10-18T09:00:00", "kp": 5.33, "observed": "predicted", "noaa_scale": "G1"},
 {"time_tag": "2026-10-19T21:00:00", "kp": 7.0, "observed": "predicted", "noaa_scale": "G3"}]
""".utf8)

@Test func decodesLatestKpAndNext24hMaximum() throws {
    let at = try #require(SpaceWeather.parse("2026-10-17T23:34:00"))
    let w = try SpaceWeather.decode(now: minutes, forecast: forecast, at: at)
    #expect(w.kpNow == 0.67)
    #expect(w.observedAt == SpaceWeather.parse("2026-10-17T23:33:00"))
    #expect(w.kpNext24h == 5.33)
}

@Test func gScale() {
    #expect(SpaceWeather.gScale(4.67) == nil)
    #expect(SpaceWeather.gScale(5.33) == 1)
    #expect(SpaceWeather.gScale(9) == 5)
}

@Test func decodesBackendToday() throws {
    let data = Data(#"{"spaceWeather":{"kpNow":2.33,"observedAt":"2026-10-22T00:05:00.000Z","kpNext24h":4.67,"fetchedAt":"2026-10-22T00:10:12.964Z"}}"#.utf8)
    let w = try SpaceWeather.decodeToday(data)
    #expect(w == SpaceWeather(kpNow: 2.33, observedAt: try Date("2026-10-22T00:05:00Z", strategy: .iso8601), kpNext24h: 4.67))
}

@Test func decodesBackendSolarWind() throws {
    let data = Data(#"{"spaceWeather":{"kpNow":2,"observedAt":"2026-10-22T00:05:00.000Z","kpNext24h":null,"fetchedAt":"x"},"solarWind":{"observedAt":"2026-10-22T03:36:00.000Z","source":"SOLAR1","series":[{"t":"2026-10-22T03:30:00.000Z","speed":477.8,"density":5.8,"bz":4.6,"bt":7.8},{"t":"2026-10-22T03:35:00.000Z","speed":467.5,"density":null,"bz":-3.5,"bt":7.7}]}}"#.utf8)
    let w = try #require(try SolarWind.decodeToday(data))
    #expect(w.source == "SOLAR1")
    #expect(w.series.count == 2)
    #expect(w.bz == -3.5)
    #expect(w.density == 5.8)
    #expect(try SolarWind.decodeToday(Data(#"{"spaceWeather":null}"#.utf8)) == nil)
}

@Test func decodesBackendStorm() throws {
    let data = Data(#"{"spaceWeather":null,"solarWind":null,"storm":{"startedAt":"2026-10-20T22:00:00.000Z","channels":{"sandbox":"c1","production":"c2"},"state":{"kp":5.33,"expectedKp":5.67,"early":false,"bz":null,"speed":610}}}"#.utf8)
    let s = try #require(try StormCoverage.decodeToday(data))
    #expect(s.channels["production"] == "c2")
    #expect(s.state.expectedKp == 5.67)
    #expect(s.state.bz == nil)
    #expect(s.startedAt == (try Date("2026-10-20T22:00:00Z", strategy: .iso8601)))
    #expect(try StormCoverage.decodeToday(Data(#"{"spaceWeather":null,"storm":null}"#.utf8)) == nil)
}

@Test func decodesBackendSun() throws {
    let data = Data(#"{"enlil":{"fetchedAt":"x","points":[{"t":"2026-10-22T00:00:00.000Z","speed":410,"density":5,"cloud":false}]},"ccor2":{"fetchedAt":"x","frames":[{"t":"2026-10-22T03:30:00.000Z","url":"https://services.swpc.noaa.gov/images/animations/ccor2/20261022_0330_ccor2_1024by960.jpg"}]},"cycle":{"fetchedAt":null,"months":null}}"#.utf8)
    let s = try SunForecast.decode(data)
    #expect(s.enlil.first?.speed == 410)
    #expect(s.ccor2.count == 1)
    #expect(s.cycle == nil)
}
