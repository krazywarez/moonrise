import Foundation

/// Planetary Kp from NOAA SWPC (US government data).
public struct SpaceWeather: Sendable, Equatable {
    /// Latest 1-minute estimated Kp.
    public var kpNow: Double
    public var observedAt: Date
    /// Highest predicted 3-hour Kp in the next 24 hours, if any.
    public var kpNext24h: Double?

    public init(kpNow: Double, observedAt: Date, kpNext24h: Double?) {
        self.kpNow = kpNow
        self.observedAt = observedAt
        self.kpNext24h = kpNext24h
    }

    public static let nowURL = URL(string: "https://services.swpc.noaa.gov/json/planetary_k_index_1m.json")!
    public static let forecastURL = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json")!

    struct Minute: Decodable {
        var time_tag: String
        var estimated_kp: Double
    }

    struct Forecast: Decodable {
        var time_tag: String
        var kp: Double
        var observed: String
    }

    /// SWPC time tags are UTC without a zone designator.
    static func parse(_ tag: String) -> Date? {
        try? Date(tag + "Z", strategy: .iso8601)
    }

    public static func decode(now: Data, forecast: Data, at date: Date) throws -> SpaceWeather {
        let minutes = try JSONDecoder().decode([Minute].self, from: now)
        guard let last = minutes.last, let observedAt = parse(last.time_tag) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "empty Kp feed"))
        }
        let rows = try JSONDecoder().decode([Forecast].self, from: forecast)
        let horizon = date.addingTimeInterval(24 * 3600)
        let next = rows
            .filter { $0.observed == "predicted" }
            .filter { row in parse(row.time_tag).map { $0 >= date.addingTimeInterval(-3 * 3600) && $0 <= horizon } ?? false }
            .map(\.kp)
            .max()
        return SpaceWeather(kpNow: last.estimated_kp, observedAt: observedAt, kpNext24h: next)
    }

    /// From the backend's /v1/today, which polls SWPC for every install; straight from SWPC if the backend
    /// is unset or fails.
    public static func fetch(base: URL?, session: URLSession = .shared, at date: Date = .now) async throws -> SpaceWeather {
        if let base, let w = try? decodeToday(await session.data(from: base.appending(path: "v1/today")).0) { return w }
        async let now = session.data(from: nowURL).0
        async let forecast = session.data(from: forecastURL).0
        return try decode(now: await now, forecast: await forecast, at: date)
    }

    /// The `spaceWeather` object of the backend's GET /v1/today.
    static func decodeToday(_ data: Data) throws -> SpaceWeather {
        struct Today: Decodable {
            struct Weather: Decodable { var kpNow: Double; var observedAt: String; var kpNext24h: Double? }
            var spaceWeather: Weather
        }
        let w = try JSONDecoder().decode(Today.self, from: data).spaceWeather
        guard let observedAt = try? Date(w.observedAt, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad observedAt"))
        }
        return SpaceWeather(kpNow: w.kpNow, observedAt: observedAt, kpNext24h: w.kpNext24h)
    }

    /// NOAA G-scale for a Kp value: G1 at Kp 5 through G5 at Kp 9.
    public static func gScale(_ kp: Double) -> Int? {
        kp >= 5 ? min(Int(kp.rounded(.down)) - 4, 5) : nil
    }
}
