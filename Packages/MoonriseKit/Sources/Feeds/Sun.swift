import Foundation

/// Latest full-disk images from NASA's Solar Dynamics Observatory.
/// Credit: "Courtesy of NASA/SDO and the AIA, EVE, and HMI science teams."
public enum SolarImage: String, CaseIterable, Sendable, Identifiable {
    case corona = "0171"
    case hotCorona = "0193"
    case chromosphere = "0304"
    case visible = "HMIIC"

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .corona: "171 Å"
        case .hotCorona: "193 Å"
        case .chromosphere: "304 Å"
        case .visible: "Visible"
        }
    }

    public var caption: String {
        switch self {
        case .corona: "Quiet corona and upper transition region, about 600,000 K. Shows coronal loops."
        case .hotCorona: "Corona at about 1 million K and hot flare plasma. Coronal holes look dark."
        case .chromosphere: "Chromosphere and transition region, about 50,000 K. Shows filaments and prominences."
        case .visible: "The photosphere in visible light, where sunspots appear."
        }
    }

    /// Sizes SDO publishes: 170, 256, 512, 1024, 2048, 3072, 4096.
    public func url(size: Int = 1024) -> URL {
        URL(string: "https://sdo.gsfc.nasa.gov/assets/img/latest/latest_\(size)_\(rawValue).jpg")!
    }

    public static let credit = "Courtesy of NASA/SDO and the AIA, EVE, and HMI science teams."
}

/// Three-hour planetary Kp, observed and predicted (SWPC 3-day forecast product).
public struct KpBar: Sendable, Equatable, Identifiable, Codable {
    public var start: Date
    public var kp: Double
    public var predicted: Bool
    public var id: Date { start }
}

extension SpaceWeather {
    public static func decodeKpBars(_ data: Data) throws -> [KpBar] {
        try JSONDecoder().decode([Forecast].self, from: data).compactMap { row in
            parse(row.time_tag).map { KpBar(start: $0, kp: row.kp, predicted: row.observed != "observed") }
        }
    }

    public static func fetchKpBars(session: URLSession = .shared) async throws -> [KpBar] {
        try decodeKpBars(await session.data(from: forecastURL).0)
    }
}

/// GOES long-channel (0.1–0.8 nm) X-ray flux, which defines flare classes.
public struct XRaySample: Sendable, Equatable, Identifiable, Codable {
    public var time: Date
    /// W/m².
    public var flux: Double
    public var id: Date { time }
}

public enum XRay {
    public static let dayURL = URL(string: "https://services.swpc.noaa.gov/json/goes/primary/xrays-1-day.json")!

    struct Row: Decodable {
        var time_tag: String
        var flux: Double?
        var energy: String
    }

    public static func decode(_ data: Data) throws -> [XRaySample] {
        try JSONDecoder().decode([Row].self, from: data).compactMap { row in
            guard row.energy == "0.1-0.8nm", let flux = row.flux, flux > 0,
                  let time = try? Date(row.time_tag, strategy: .iso8601) else { return nil }
            return XRaySample(time: time, flux: flux)
        }
    }

    public static func fetch(session: URLSession = .shared) async throws -> [XRaySample] {
        try decode(await session.data(from: dayURL).0)
    }

    /// Flare class for a flux, e.g. 1.5e-6 → "C1.5".
    public static func flareClass(_ flux: Double) -> String {
        let classes: [(String, Double)] = [("X", 1e-4), ("M", 1e-5), ("C", 1e-6), ("B", 1e-7), ("A", 1e-8)]
        for (letter, base) in classes where flux >= base {
            return String(format: "%@%.1f", letter, flux / base)
        }
        return String(format: "A%.1f", flux / 1e-8)
    }
}

/// NOAA SWPC OVATION aurora model: probability of visible aurora (0–100) on a 1° grid.
public struct Ovation: Sendable, Equatable, Codable {
    public struct Cell: Sendable, Equatable, Codable {
        public var lon: Double
        public var lat: Double
        public var probability: Double
    }

    public var forecastTime: Date
    public var cells: [Cell]

    public static let url = URL(string: "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json")!

    struct Raw: Decodable {
        var forecastTime: String
        var coordinates: [[Double]]
        enum CodingKeys: String, CodingKey {
            case forecastTime = "Forecast Time"
            case coordinates
        }
    }

    /// Keeps cells with a non-zero probability.
    public static func decode(_ data: Data) throws -> Ovation {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        let cells = raw.coordinates.compactMap { c -> Cell? in
            guard c.count == 3, c[2] > 0 else { return nil }
            return Cell(lon: c[0], lat: c[1], probability: c[2])
        }
        return Ovation(forecastTime: (try? Date(raw.forecastTime, strategy: .iso8601)) ?? .now, cells: cells)
    }

    public static func fetch(session: URLSession = .shared) async throws -> Ovation {
        try decode(await session.data(from: url).0)
    }
}
