import Foundation

/// Solar wind at L1 from the backend's /v1/today: 5-minute means over 6 hours from SWPC's real-time solar wind
/// (SOLAR-1, ACE or IMAP).
public struct SolarWind: Sendable, Equatable, Decodable {
    public struct Point: Sendable, Equatable, Decodable, Identifiable {
        public var t: Date
        public var speed: Double?
        public var density: Double?
        public var bz: Double?
        public var bt: Double?
        public var id: Date { t }
    }

    public var observedAt: Date
    public var source: String
    public var series: [Point]

    /// The latest bin with each value.
    public var speed: Double? { series.last { $0.speed != nil }?.speed }
    public var density: Double? { series.last { $0.density != nil }?.density }
    public var bz: Double? { series.last { $0.bz != nil }?.bz }
    public var bt: Double? { series.last { $0.bt != nil }?.bt }

    static func decodeToday(_ data: Data) throws -> SolarWind? {
        struct Today: Decodable { var solarWind: SolarWind? }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
            }
            return date
        }
        return try d.decode(Today.self, from: data).solarWind
    }

    public static func fetch(base: URL, session: URLSession = .shared) async throws -> SolarWind? {
        try decodeToday(await session.data(from: base.appending(path: "v1/today")).0)
    }
}
