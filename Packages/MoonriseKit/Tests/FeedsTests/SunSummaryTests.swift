import Foundation
import Testing
@testable import Feeds

private func at(_ s: String) -> Date { try! Date(s, strategy: .iso8601) }

private let now = at("2026-10-19T15:00:00Z")
private let night = DateInterval(start: at("2026-10-19T23:00:00Z"), end: at("2026-10-20T11:00:00Z"))
/// Chicago is at about 50.7° geomagnetic.
private let chicago = 50.7

private func scales(r: Int = 0, s: Int = 0, g: Int = 0) -> NOAAScales {
    NOAAScales(asOf: at("2026-10-19T14:55:00Z"), current: .init(r: r, s: s, g: g), past24h: .init(r: r, s: s, g: g))
}

private let probabilities = SolarProbabilities(
    issued: at("2026-10-19T00:00:00Z"),
    days: [.init(c: 85, m: 25, x: 5, proton: 5), .init(c: 80, m: 20, x: 5, proton: 5), .init(c: 80, m: 20, x: 5, proton: 5)]
)

private let quietKp = [
    KpBar(start: at("2026-10-19T12:00:00Z"), kp: 2.33, predicted: false),
    KpBar(start: at("2026-10-20T00:00:00Z"), kp: 3.0, predicted: true),
]

private let quietXRay = [XRaySample(time: at("2026-10-19T14:00:00Z"), flux: 3e-6)]

private func summary(
    scales s: NOAAScales? = scales(), kp: [KpBar] = quietKp, xray: [XRaySample] = quietXRay,
    latitude: Double = chicago, night n: DateInterval = night, at date: Date = now
) -> String? {
    SunSummary.text(
        scales: s, kp: kp, probabilities: probabilities, xray: xray,
        geomagneticLatitude: latitude, night: n, at: date,
        timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_GB")
    )
}

@Test func quietNamesTodaysFlareChance() {
    #expect(summary() == "Quiet. 25% chance of an M-class flare today.")
}

@Test func quietWithoutProbabilities() {
    let text = SunSummary.text(
        scales: scales(), kp: quietKp, probabilities: nil, xray: quietXRay,
        geomagneticLatitude: chicago, night: night, at: now,
        timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_GB")
    )
    #expect(text == "Quiet. No storms, and no flare of class M or above in the last 6 hours.")
}

@Test func nothingLoadedGivesNoSummary() {
    #expect(summary(scales: nil, kp: [], xray: []) == nil)
}

@Test func stormForecastAfterDarkAtYourLatitude() {
    let kp = quietKp + [KpBar(start: at("2026-10-20T03:00:00Z"), kp: 5.33, predicted: true)]
    #expect(summary(kp: kp) == "Minor storm (G1) forecast for 3:00–6:00, Kp 5.3. Aurora possible low in the northern sky.")
}

@Test func stormNowAndDark() {
    let kp = [KpBar(start: at("2026-10-20T00:00:00Z"), kp: 6.67, predicted: true)]
    let text = summary(scales: scales(g: 2), kp: kp, at: at("2026-10-20T01:00:00Z"))
    #expect(text == "Moderate storm (G2) now, Kp 6.7. Aurora possible low in the northern sky.")
}

@Test func stormUnderwayBeforeDarkRunsIntoTheNight() {
    let kp = [KpBar(start: at("2026-10-19T21:00:00Z"), kp: 5.0, predicted: true)]
    let text = summary(kp: kp, at: at("2026-10-19T21:30:00Z"))
    #expect(text == "Minor storm (G1) forecast until 0:00, Kp 5.0. Aurora possible low in the northern sky.")
}

@Test func southernObserverLooksSouth() {
    let kp = [KpBar(start: at("2026-10-20T03:00:00Z"), kp: 5.33, predicted: true)]
    #expect(summary(kp: kp, latitude: -55)?.hasSuffix("Aurora possible low in the southern sky.") == true)
}

@Test func stormTooFarFromThePoleIsASecondClause() {
    // At 40° geomagnetic, Kp 5.3 does not reach: the oval's visible edge is at 49.6°.
    let kp = quietKp + [KpBar(start: at("2026-10-20T03:00:00Z"), kp: 5.33, predicted: true)]
    #expect(summary(kp: kp, latitude: 40) == "Quiet now. Minor storm (G1) forecast from 3:00, Kp 5.3.")
}

@Test func daytimeStormIsASecondClause() {
    let kp = quietKp + [KpBar(start: at("2026-10-19T18:00:00Z"), kp: 5.33, predicted: true)]
    #expect(summary(kp: kp) == "Quiet now. Minor storm (G1) forecast from 18:00, Kp 5.3.")
}

@Test func stormNowOutOfReach() {
    #expect(summary(scales: scales(g: 1), latitude: 40) == "Minor storm (G1) as of 14:55. Aurora at your latitude would need more than Kp 9.")
    #expect(summary(scales: scales(g: 1), latitude: 45) == "Minor storm (G1) as of 14:55. Aurora at your latitude needs Kp 7.6.")
}

@Test func stormNowInReachButOverBeforeDark() {
    #expect(summary(scales: scales(g: 1)) == "Minor storm (G1) as of 14:55. Kp is forecast below 5 after dark.")
}

@Test func radiationStorm() {
    #expect(summary(scales: scales(s: 1)) == "Minor radiation storm (S1) as of 14:55. It affects polar flights and satellites, not people on the ground.")
}

@Test func recentFlare() {
    let xray = quietXRay + [XRaySample(time: at("2026-10-19T14:05:00Z"), flux: 1.2e-4)]
    #expect(summary(xray: xray) == "Strong flare (X1.2) at 14:05. Brief radio blackout on Earth's day side.")
}

@Test func flareOlderThanSixHoursIsQuiet() {
    let xray = quietXRay + [XRaySample(time: at("2026-10-19T08:30:00Z"), flux: 2e-5)]
    #expect(summary(xray: xray) == "Quiet. 25% chance of an M-class flare today.")
}

@Test func radioBlackoutWithoutXRayData() {
    #expect(summary(scales: scales(r: 3), xray: []) == "Strong radio blackout (R3) as of 14:55. It affects radio on Earth's day side.")
}

@Test func stormOutranksRadiationAndFlare() {
    let xray = [XRaySample(time: at("2026-10-19T14:05:00Z"), flux: 5e-5)]
    #expect(summary(scales: scales(r: 2, s: 1, g: 1), xray: xray)?.hasPrefix("Minor storm (G1)") == true)
    #expect(summary(scales: scales(r: 2, s: 1), xray: xray)?.hasPrefix("Minor radiation storm (S1)") == true)
    #expect(summary(scales: scales(r: 2), xray: xray)?.hasPrefix("Moderate flare (M5.0)") == true)
}

@Test func visibleLatitudeMatchesServer() {
    // server/src/aurora.ts: visibleFrom(kp) = 66.5 - 2.04 * kp - 6
    #expect(abs(SunSummary.visibleFrom(kp: 5) - 50.3) < 1e-9)
}
