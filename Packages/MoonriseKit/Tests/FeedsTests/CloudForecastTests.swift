import Foundation
import SkyEngine
import Testing
@testable import Feeds

@Test func locationIsRoundedToATenthOfADegree() {
    let c = SavedForecast.cell(Observer(latitude: 41.8781, longitude: -87.6298))
    #expect(c.latitude == 41.9)
    #expect(c.longitude == -87.6)
}

@Test func savedForecastRoundTripsAndMatchesItsCell() throws {
    let hour = HourSample(date: Date(timeIntervalSince1970: 1_792_202_400), cloudLow: 0.1, cloudMid: 0.2, cloudHigh: 0.6, cloudTotal: 0.7,
                          precipitationChance: 0.05, visibility: 24_000)
    let saved = SavedForecast(latitude: 41.9, longitude: -87.6, forecast: CloudForecast(fetched: hour.date, hours: [hour]),
                              credit: WeatherCredit(markURL: URL(string: "https://example.com/mark.png")!, legalURL: URL(string: "https://example.com/legal")!))
    let url = URL.temporaryDirectory.appending(path: "cloud-forecast-\(UUID()).json")
    defer { SavedForecast.delete(at: url) }
    try saved.save(to: url)
    #expect(SavedForecast.load(from: url) == saved)
    #expect(saved.isFor(Observer(latitude: 41.88, longitude: -87.63)))
    #expect(!saved.isFor(Observer(latitude: 42.0, longitude: -87.63)))
    SavedForecast.delete(at: url)
    #expect(SavedForecast.load(from: url) == nil)
}
