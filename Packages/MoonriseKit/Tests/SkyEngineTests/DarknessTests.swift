import Foundation
import Testing
@testable import SkyEngine

private let central = TimeZone(identifier: "America/Chicago")!
private let hm = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"), timeZone: central)

@Test func astronomicalDuskAndDawnInChicago() throws {
    // NOAA solar position algorithm: Sun at −18° at 00:38:30 and 10:33:40 UT on 18 October 2026.
    let t = try Tonight(at: ut(18, 0), from: chicago)
    let dark = try #require(t.dark)
    #expect(abs(dark.start.timeIntervalSince(ut(24, 38) + 30)) < 60)
    #expect(abs(dark.end.timeIntervalSince(ut(34, 33) + 40)) < 60)
}

@Test func alreadyDarkStartsNow() throws {
    // 21:00 CDT; NOAA has the Sun back at −18° at 10:32:30 UT.
    let t = try Tonight(at: observed, from: chicago)
    let dark = try #require(t.dark)
    #expect(dark.start == observed)
    #expect(abs(dark.end.timeIntervalSince(ut(10, 32) + 30)) < 60)
}

@Test func noDarknessInTromsoInJune() throws {
    let tromso = Observer(latitude: 69.65, longitude: 18.96)
    #expect(try SkyEngine.darkness(from: utc("2026-06-21T12:00:00Z"), to: utc("2026-06-22T12:00:00Z"), observer: tromso) == nil)
}

@Test func waxingMoonSetsInTheEvening() throws {
    // 35% lit and up at 21:00 CDT on 16 October 2026; JPL Horizons has it setting at 02:49 UT.
    let t = try Tonight(at: observed, from: chicago)
    #expect(t.moonUp.count == 1)
    #expect(t.moonUp[0].start == t.start)
    #expect(t.moonrise == nil)
    let set = try #require(t.moonset)
    #expect(abs(set.timeIntervalSince(ut(2, 49))) < 90)
    #expect(t.moonAndDarkness(time: hm) == "Dark 21:00–5:32. Moon 35% lit, sets 21:48.")
}

@Test func moonUpAlternatesWithRiseAndSet() throws {
    let start = ut(18, 0)
    let up = try SkyEngine.moonUp(from: start, to: start + 3 * 86_400, observer: chicago)
    #expect(up.count >= 3)
    for (a, b) in zip(up, up.dropFirst()) {
        #expect(b.start > a.end)
        #expect(try SkyEngine.horizontal(.moon, at: a.end + b.start.timeIntervalSince(a.end) / 2, from: chicago).altitude < 0)
    }
    for i in up {
        #expect(try SkyEngine.horizontal(.moon, at: i.start + i.duration / 2, from: chicago).altitude > 0)
    }
}

@Test func moonAndDarknessText() {
    let base = ut(24, 0)
    func at(_ h: Double) -> Date { base + h * 3600 }
    let night = DateInterval(start: at(-1), end: at(11))
    let dark = DateInterval(start: at(0.5), end: at(10.5))
    func text(_ up: [DateInterval], dark: DateInterval? = dark) -> String {
        SkyEngine.moonAndDarkness(night: night, dark: dark, moonUp: up, moonIllumination: 0.624, time: hm)
    }
    #expect(text([]) == "Dark 19:30–5:30. Moon down throughout.")
    #expect(text([DateInterval(start: at(-1), end: at(0.2))]) == "Dark 19:30–5:30. Moon down throughout.")
    #expect(text([night]) == "Dark 19:30–5:30. Moon 62% lit, up throughout.")
    #expect(text([DateInterval(start: at(-1), end: at(4))]) == "Dark 19:30–5:30. Moon 62% lit, sets 23:00.")
    #expect(text([DateInterval(start: at(8), end: at(11))]) == "Dark 19:30–5:30. Moon 62% lit, rises 3:00.")
    #expect(text([DateInterval(start: at(-1), end: at(2)), DateInterval(start: at(9), end: at(11))])
        == "Dark 19:30–5:30. Moon 62% lit, sets 21:00, rises 4:00.")
    #expect(text([DateInterval(start: at(-1), end: at(0))], dark: nil) == "The sky does not get fully dark. Moon 62% lit, sets 19:00.")
}

@Test func moonNoteOnFaintPasses() {
    func pass(_ name: String, peak: Date, visible: Bool = true) -> SatellitePass {
        SatellitePass(name: name, rise: peak - 180, set: peak + 180, peak: peak, maxAltitude: 60, riseAzimuth: 240, setAzimuth: 60, visible: visible)
    }
    // Moon 35% lit and up at 02:00 UT on 17 October 2026, set by 04:00.
    #expect(pass("HST", peak: observed).moonNote(from: chicago) == "Moon up, 35% lit")
    #expect(pass("SL-8 R/B", peak: observed).moonNote(from: chicago) == "Moon up, 35% lit")
    #expect(pass("HST", peak: ut(4, 0)).moonNote(from: chicago) == nil)
    #expect(pass("HST", peak: observed, visible: false).moonNote(from: chicago) == nil)
    #expect(pass("ISS (ZARYA)", peak: observed).moonNote(from: chicago) == nil)
    #expect(pass("CSS (TIANHE)", peak: observed).moonNote(from: chicago) == nil)
    // 2026-10-12 23:30 UT: 6% lit crescent, 3° up after sunset.
    #expect(pass("HST", peak: utc("2026-10-12T23:30:00Z")).moonNote(from: chicago) == nil)
}

@Test func moonlitWhenUpAndLitDuringDarkness() throws {
    // 35% lit and up until 21:48 CDT.
    #expect(try Tonight(at: observed, from: chicago).moonlit)
    // New moon on 12 August 2026.
    #expect(try !Tonight(at: utc("2026-08-12T18:00:00Z"), from: chicago).moonlit)
}
