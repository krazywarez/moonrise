import CoreLocation
import Foundation
import SkyEngine
import WeatherKit

/// The Apple Weather mark and legal page, which WeatherKit's terms require wherever its data is shown.
public struct WeatherCredit: Sendable, Codable, Equatable {
    /// The combined mark in its dark variant, a white mark for dark backgrounds.
    public var markURL: URL
    public var legalURL: URL
}

/// A cloud forecast from Apple Weather for one rounded place, as kept on disk.
public struct SavedForecast: Sendable, Codable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var forecast: CloudForecast
    public var credit: WeatherCredit

    /// The location sent to Apple: rounded to 0.1°, about 11 km north–south.
    public static func cell(_ observer: Observer) -> (latitude: Double, longitude: Double) {
        ((observer.latitude * 10).rounded() / 10, (observer.longitude * 10).rounded() / 10)
    }

    public func isFor(_ observer: Observer) -> Bool {
        let c = Self.cell(observer)
        return c.latitude == latitude && c.longitude == longitude
    }

    public static let file = URL.cachesDirectory.appending(path: "cloud-forecast.json")

    public static func load(from url: URL = file) -> SavedForecast? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SavedForecast.self, from: $0) }
    }

    public func save(to url: URL = file) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func delete(at url: URL = file) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Ten days of hourly cloud for the observer's rounded location. One WeatherKit call, plus the attribution.
    public static func fetch(for observer: Observer, now: Date = .now) async throws -> SavedForecast {
        let c = cell(observer)
        let start = Calendar(identifier: .gregorian).dateInterval(of: .hour, for: now)?.start ?? now
        let service = WeatherService.shared
        let hourly = try await service.weather(for: CLLocation(latitude: c.latitude, longitude: c.longitude),
                                               including: .hourly(startDate: start, endDate: start.addingTimeInterval(240 * 3600)))
        let attribution = try await service.attribution
        let hours = hourly.forecast.map { h in
            HourSample(date: h.date, cloudLow: h.cloudCoverByAltitude.low, cloudMid: h.cloudCoverByAltitude.medium, cloudHigh: h.cloudCoverByAltitude.high,
                       cloudTotal: h.cloudCover, precipitationChance: h.precipitationChance, visibility: h.visibility.converted(to: .meters).value)
        }
        return SavedForecast(latitude: c.latitude, longitude: c.longitude, forecast: CloudForecast(fetched: now, hours: hours),
                             credit: WeatherCredit(markURL: attribution.combinedMarkDarkURL, legalURL: attribution.legalPageURL))
    }
}
