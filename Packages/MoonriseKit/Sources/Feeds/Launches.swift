import Foundation

/// An upcoming launch as served by the Moonrise backend (from Launch Library 2).
public struct Launch: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var net: Date
    public var windowStart: Date?
    public var windowEnd: Date?
    /// Launch Library 2 status abbreviation: Go, TBC, TBD, Hold, Success, Failure, …
    public var status: String
    public var statusName: String
    public var provider: String
    public var rocket: String
    public var mission: String?
    public var missionType: String?
    public var missionDescription: String?
    public var orbit: String?
    public var pad: String
    public var location: String
    public var padLatitude: Double?
    public var padLongitude: Double?
}

public struct LaunchList: Codable, Sendable {
    public var fetchedAt: Date?
    public var launches: [Launch]
}

public enum LaunchFeed {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(s, strategy: .iso8601) { return date }
            if let date = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    public static func decode(_ data: Data) throws -> LaunchList {
        try decoder.decode(LaunchList.self, from: data)
    }

    public static func fetch(base: URL, session: URLSession = .shared) async throws -> LaunchList {
        try decode(await session.data(from: base.appending(path: "v1/launches")).0)
    }
}
