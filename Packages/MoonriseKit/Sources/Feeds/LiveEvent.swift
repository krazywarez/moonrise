import Foundation

/// A mission covered live by the backend (GET /v1/live): its phases and geocentric trajectory.
public struct LiveCoverage: Sendable {
    public struct Event: Sendable, Decodable, Hashable {
        public struct Phase: Sendable, Decodable, Hashable {
            public var at: Date
            public var label: String
        }

        public var id: String
        public var title: String
        public var launch: Date
        public var end: Date
        public var phases: [Phase]
    }

    public struct Point: Sendable, Hashable {
        public var date: Date
        /// km, J2000 ecliptic axes, centred on Earth.
        public var position: SIMD3<Double>
    }

    public var event: Event
    public var at: Date
    public var points: [Point]

    /// The last phase that has started by `at`, and the next one.
    public var phase: (current: Event.Phase?, next: Event.Phase?) {
        (event.phases.last { $0.at <= at }, event.phases.first { $0.at > at })
    }

    /// Distance from Earth's centre at the latest point, km.
    public var distanceKm: Double? { points.last.map { ($0.position * $0.position).sum().squareRoot() } }

    private struct Response: Decodable {
        var event: Event?
        var at: Date?
        var points: [[Double]]?
    }

    /// nil when no event is running.
    public static func decode(_ data: Data) throws -> LiveCoverage? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(s, strategy: .iso8601) { return date }
            return try Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
        let r = try d.decode(Response.self, from: data)
        guard let event = r.event, let at = r.at else { return nil }
        let points = (r.points ?? []).filter { $0.count == 4 }.map {
            Point(date: Date(timeIntervalSince1970: $0[0]), position: SIMD3($0[1], $0[2], $0[3]))
        }
        return LiveCoverage(event: event, at: at, points: points)
    }

    /// `at` replays a past event (testing); nil means now.
    public static func fetch(base: URL, at: Date? = nil, session: URLSession = .shared) async throws -> LiveCoverage? {
        var url = base.appending(path: "v1/live")
        if let at { url.append(queryItems: [URLQueryItem(name: "at", value: at.ISO8601Format())]) }
        return try decode(await session.data(from: url).0)
    }
}
