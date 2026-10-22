import Foundation

/// The backend's /v1/sun: WSA-Enlil solar wind forecast at Earth (hourly), CCOR-2 coronagraph frames (hourly over a
/// day) and solar cycle 25 sunspot numbers (monthly), all from NOAA SWPC.
public struct SunForecast: Sendable, Decodable {
    public struct EnlilPoint: Sendable, Decodable, Identifiable {
        public var t: Date
        public var speed: Double
        public var density: Double
        /// In a coronal mass ejection's cloud.
        public var cloud: Bool
        public var id: Date { t }
    }

    public struct Frame: Sendable, Decodable, Identifiable {
        public var t: Date
        public var url: URL
        public var id: Date { t }
    }

    public struct Month: Sendable, Decodable, Identifiable {
        public var month: String
        public var ssn: Double?
        public var smoothed: Double?
        public var id: String { month }
    }

    public struct Predicted: Sendable, Decodable, Identifiable {
        public var month: String
        public var ssn: Double
        public var high: Double
        public var low: Double
        public var id: String { month }
    }

    public struct Cycle: Sendable, Decodable {
        public var observed: [Month]
        public var predicted: [Predicted]
    }

    public var enlil: [EnlilPoint]
    public var ccor2: [Frame]
    public var cycle: Cycle?

    private struct Raw: Decodable {
        struct Part<T: Decodable>: Decodable { var points: T?; var frames: T?; var months: T? }
        var enlil: Part<[EnlilPoint]>
        var ccor2: Part<[Frame]>
        var cycle: Part<Cycle>
    }

    static func decode(_ data: Data) throws -> SunForecast {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
            }
            return date
        }
        let r = try d.decode(Raw.self, from: data)
        return SunForecast(enlil: r.enlil.points ?? [], ccor2: r.ccor2.frames ?? [], cycle: r.cycle.months)
    }

    public static func fetch(base: URL, session: URLSession = .shared) async throws -> SunForecast {
        try decode(await session.data(from: base.appending(path: "v1/sun")).0)
    }
}

extension SunForecast.Month {
    /// The first of the month, UTC.
    public var date: Date? { try? Date(month + "-01T00:00:00Z", strategy: .iso8601) }
}

extension SunForecast.Predicted {
    public var date: Date? { try? Date(month + "-01T00:00:00Z", strategy: .iso8601) }
}
