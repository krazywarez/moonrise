import Foundation

/// NOAA space weather scales (US government data): R for radio blackouts, S for solar radiation storms,
/// G for geomagnetic storms, each from 0 (none) to 5 (extreme).
public struct NOAAScales: Sendable, Equatable, Codable {
    public struct Levels: Sendable, Equatable, Codable {
        public var r: Int
        public var s: Int
        public var g: Int

        public init(r: Int, s: Int, g: Int) {
            self.r = r
            self.s = s
            self.g = g
        }
    }

    /// When NOAA stamped the current levels.
    public var asOf: Date
    public var current: Levels
    /// Highest levels in the 24 hours before `asOf`.
    public var past24h: Levels

    public init(asOf: Date, current: Levels, past24h: Levels) {
        self.asOf = asOf
        self.current = current
        self.past24h = past24h
    }

    public static let url = URL(string: "https://services.swpc.noaa.gov/products/noaa-scales.json")!

    struct Entry: Decodable {
        struct Scale: Decodable { var Scale: String? }
        var DateStamp: String
        var TimeStamp: String
        var R: Scale
        var S: Scale
        var G: Scale

        var levels: Levels {
            Levels(r: R.Scale.flatMap(Int.init) ?? 0, s: S.Scale.flatMap(Int.init) ?? 0, g: G.Scale.flatMap(Int.init) ?? 0)
        }
    }

    /// Key "0" is now and "-1" the past 24 hours; "1" to "3" are forecasts, which the Sun tab takes from
    /// the Kp forecast and solar_probabilities.json instead.
    public static func decode(_ data: Data) throws -> NOAAScales {
        let entries = try JSONDecoder().decode([String: Entry].self, from: data)
        guard let now = entries["0"], let past = entries["-1"],
              let asOf = try? Date("\(now.DateStamp)T\(now.TimeStamp)Z", strategy: .iso8601) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "missing current scales"))
        }
        return NOAAScales(asOf: asOf, current: now.levels, past24h: past.levels)
    }

    public static func fetch(session: URLSession = .shared) async throws -> NOAAScales {
        try decode(await session.data(from: url).0)
    }

    /// NOAA's word for a scale level.
    public static func levelName(_ level: Int) -> String {
        ["none", "minor", "moderate", "strong", "severe", "extreme"][max(0, min(level, 5))]
    }
}

/// NOAA SWPC's daily flare and proton event probabilities for the next three UT days.
public struct SolarProbabilities: Sendable, Equatable, Codable {
    /// Percent chances for one UT day.
    public struct Day: Sendable, Equatable, Codable {
        public var c: Int
        public var m: Int
        public var x: Int
        /// Proton event: ≥10 MeV flux at or above 10 pfu, the S1 threshold.
        public var proton: Int

        public init(c: Int, m: Int, x: Int, proton: Int) {
            self.c = c
            self.m = m
            self.x = x
            self.proton = proton
        }
    }

    /// 00 UT on the first forecast day, as the feed dates it.
    public var issued: Date
    /// The first forecast day first.
    public var days: [Day]

    public init(issued: Date, days: [Day]) {
        self.issued = issued
        self.days = days
    }

    public static let url = URL(string: "https://services.swpc.noaa.gov/json/solar_probabilities.json")!

    struct Row: Decodable {
        var date: String
        var c1, c2, c3, m1, m2, m3, x1, x2, x3, p1, p2, p3: Int?

        enum CodingKeys: String, CodingKey {
            case date
            case c1 = "c_class_1_day", c2 = "c_class_2_day", c3 = "c_class_3_day"
            case m1 = "m_class_1_day", m2 = "m_class_2_day", m3 = "m_class_3_day"
            case x1 = "x_class_1_day", x2 = "x_class_2_day", x3 = "x_class_3_day"
            case p1 = "10mev_protons_1_day", p2 = "10mev_protons_2_day", p3 = "10mev_protons_3_day"
        }

        var days: [Day]? {
            guard let c1, let c2, let c3, let m1, let m2, let m3, let x1, let x2, let x3, let p1, let p2, let p3 else { return nil }
            return [Day(c: c1, m: m1, x: x1, proton: p1), Day(c: c2, m: m2, x: x2, proton: p2), Day(c: c3, m: m3, x: x3, proton: p3)]
        }
    }

    /// The newest complete row of the 30 the feed holds.
    public static func decode(_ data: Data) throws -> SolarProbabilities {
        let rows = try JSONDecoder().decode([Row].self, from: data).compactMap { row -> SolarProbabilities? in
            guard let issued = SpaceWeather.parse(row.date), let days = row.days else { return nil }
            return SolarProbabilities(issued: issued, days: days)
        }
        guard let newest = rows.max(by: { $0.issued < $1.issued }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "no complete probability rows"))
        }
        return newest
    }

    public static func fetch(session: URLSession = .shared) async throws -> SolarProbabilities {
        try decode(await session.data(from: url).0)
    }

    /// The forecast for the UT day containing `date`, if it is one of the three.
    public func day(at date: Date) -> Day? {
        let elapsed = date.timeIntervalSince(issued)
        guard elapsed >= 0 else { return nil }
        let i = Int(elapsed / 86_400)
        return i < days.count ? days[i] : nil
    }
}
