import Foundation
import Testing
@testable import SkyEngine

private let utcTime = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC")!)
private let fetched = utc("2026-10-20T12:00:00Z")
private let dusk = utc("2026-10-21T00:00:00Z")

/// Hourly samples from `dusk`, one total cover per hour; low cloud equals total unless `high` is set.
private func forecast(_ covers: [Double], high: Bool = false, rain: Set<Int> = [], from start: Date = dusk) -> CloudForecast {
    CloudForecast(fetched: fetched, hours: covers.enumerated().map { i, c in
        HourSample(date: start.addingTimeInterval(Double(i) * 3600), cloudLow: high ? 0 : c, cloudMid: 0, cloudHigh: high ? c : 0,
                   cloudTotal: c, precipitationChance: rain.contains(i) ? 0.8 : 0, visibility: 20_000)
    })
}

private func night(_ hours: Double) -> DateInterval { DateInterval(start: dusk, duration: hours * 3600) }

@Test func clearMoonlessNightIsGo() {
    let o = forecast([0.1, 0, 0.2, 0.1]).outlook(over: night(4), target: .faint, moonUp: [], moonIllumination: 0.9, now: fetched, time: utcTime)
    #expect(o == Outlook(rating: .go, reason: "Clear throughout"))
}

@Test func overcastNightIsNo() {
    let o = forecast([0.9, 1, 0.95]).outlook(over: night(3), target: .faint, moonUp: [], moonIllumination: 0, now: fetched, time: utcTime)
    #expect(o == Outlook(rating: .no, reason: "90–100% cloud"))
}

@Test func moonlightAloneNeverMakesGo() {
    // Clear all night with a 90% Moon up throughout: moonlit, so marginal, not go.
    let o = forecast([0, 0, 0, 0]).outlook(over: night(4), target: .faint, moonUp: [night(4)], moonIllumination: 0.9, now: fetched, time: utcTime)
    #expect(o == Outlook(rating: .marginal, reason: "Clear but moonlit"))
}

@Test func clearAfterMoonsetIsGo() {
    let moon = DateInterval(start: dusk, duration: 2 * 3600)
    let o = forecast([0, 0, 0, 0, 0]).outlook(over: night(5), target: .faint, moonUp: [moon], moonIllumination: 0.6, now: fetched, time: utcTime)
    #expect(o == Outlook(rating: .go, reason: "Clear 2:00–5:00"))
}

@Test func oneGoodHourIsMarginal() {
    let o = forecast([0.9, 0.1, 0.9, 0.8]).outlook(over: night(4), target: .faint, moonUp: [], moonIllumination: 0, now: fetched, time: utcTime)
    #expect(o == Outlook(rating: .marginal, reason: "Clear 1:00–2:00, cloudy otherwise"))
}

@Test func partialCloudIsNotClear() {
    let o = forecast([0.5, 0.5, 0.5]).outlook(over: night(3), target: .faint, moonUp: [], moonIllumination: 0, now: fetched, time: utcTime)
    #expect(o?.rating == Rating.no)
}

@Test func rainOutweighsClearSky() {
    let o = forecast([0, 0, 0], rain: [0, 1, 2]).outlook(over: night(3), target: .faint, moonUp: [], moonIllumination: 0, now: fetched, time: utcTime)
    #expect(o == Outlook(rating: .no, reason: "Rain or fog likely"))
}

@Test func shortDarknessNeedsHalfOfIt() {
    let o = forecast([0, 0.9]).outlook(over: night(1.5), target: .faint, moonUp: [], moonIllumination: 0, now: fetched, time: utcTime)
    #expect(o?.rating == Rating.go)
}

@Test func noOutlookWhereTheForecastStops() {
    #expect(forecast([0, 0]).outlook(over: night(3), target: .faint, moonUp: [], moonIllumination: 0, now: fetched) == nil)
    #expect(forecast([0, 0]).outlook(at: dusk.addingTimeInterval(3 * 3600), target: .bright, now: fetched) == nil)
}

@Test func noRatingBeyond72Hours() {
    let start = fetched.addingTimeInterval(80 * 3600)
    let f = forecast([0.2, 0.4], from: start)
    let o = f.outlook(over: DateInterval(start: start, duration: 2 * 3600), target: .faint, moonUp: [], moonIllumination: 0, now: fetched)
    #expect(o == Outlook(rating: nil, reason: "20–40% cloud"))
    #expect(f.outlook(at: start, target: .faint, now: fetched) == Outlook(rating: nil, reason: "20% cloud"))
}

@Test func noRatingFromAForecastOverADayOld() {
    let o = forecast([0, 0, 0]).outlook(over: night(3), target: .faint, moonUp: [], moonIllumination: 0, now: fetched.addingTimeInterval(25 * 3600))
    #expect(o == Outlook(rating: nil, reason: "0% cloud"))
    #expect(!forecast([]).isStale(now: fetched.addingTimeInterval(6 * 3600)))
    #expect(forecast([]).isStale(now: fetched.addingTimeInterval(6 * 3600 + 1)))
}

@Test func brightTargetsIgnoreHighCloud() {
    let f = forecast([0.9], high: true)
    let pass = dusk.addingTimeInterval(1200)
    #expect(f.outlook(at: pass, target: .bright, now: fetched) == Outlook(rating: .go, reason: "0% low and mid cloud"))
    #expect(f.outlook(at: pass, target: .faint, now: fetched) == Outlook(rating: .no, reason: "90% cloud"))
    #expect(forecast([0.5]).outlook(at: pass, target: .bright, now: fetched)?.rating == Rating.marginal)
}

@Test func meteorShowerOutlookUsesItsNight() throws {
    // Orionids peak night, 21–22 October 2026, from Chicago.
    let event = try #require(SkyEngine.events(from: utc("2026-10-20T00:00:00Z"), days: 3, observer: chicago).first { $0.kind == .meteorShower })
    let w = try #require(event.window)
    let hours = (0..<24).map { i in
        HourSample(date: w.start.addingTimeInterval(Double(i - 1) * 3600), cloudLow: 0, cloudMid: 0, cloudHigh: 0, cloudTotal: 0, precipitationChance: 0, visibility: 20_000)
    }
    let f = CloudForecast(fetched: w.start.addingTimeInterval(-6 * 3600), hours: hours)
    let o = try #require(try SkyEngine.outlook(for: event, forecast: f, observer: chicago, now: f.fetched))
    #expect(o.rating == Rating.go)
}
