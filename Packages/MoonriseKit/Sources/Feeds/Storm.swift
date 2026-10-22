import Foundation

/// A geomagnetic storm the backend is broadcasting Live Activity updates for: the `storm` object of /v1/today,
/// nil when there is none.
public struct StormCoverage: Sendable, Equatable, Decodable {
    public struct State: Sendable, Equatable, Decodable {
        public var kp: Double
        /// The higher of `kp` and the forecast for the 3-hour periods now and next.
        public var expectedKp: Double
        /// Bz at or below −10 nT with a fast wind for 30 minutes: Kp usually rises within the hour.
        public var early: Bool
        public var bz: Double?
        public var speed: Double?
    }

    public var startedAt: Date
    /// APNs broadcast channel by environment ("sandbox", "production").
    public var channels: [String: String]
    /// As last broadcast.
    public var state: State

    static func decodeToday(_ data: Data) throws -> StormCoverage? {
        struct Today: Decodable { var storm: StormCoverage? }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
            }
            return date
        }
        return try d.decode(Today.self, from: data).storm
    }

    public static func fetch(base: URL, session: URLSession = .shared) async throws -> StormCoverage? {
        try decodeToday(await session.data(from: base.appending(path: "v1/today")).0)
    }
}
