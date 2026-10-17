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
