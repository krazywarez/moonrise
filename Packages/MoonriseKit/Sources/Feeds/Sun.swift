import CoreGraphics
import Foundation
import ImageIO

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

    /// Disk radius as a fraction of the frame's width.
    var diskRadius: Double { self == .visible ? 0.45 : 0.39 }

    /// Whether a frame shows the whole disk. SDO publishes AIA frames that are black apart from the label along the
    /// bottom, and some with part of the disk behind a curved dark edge. On a 64 px thumbnail, the share of the disk
    /// (above the label) brighter than 16/255: whole frames measure 0.99 or more, 193 Å with its coronal holes being the
    /// lowest, and covered ones 0.6 or less, so 0.95 is the cut.
    public func isUsable(_ data: Data) -> Bool {
        let n = 64
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: n] as CFDictionary),
              let context = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        let r = diskRadius * Double(n), c = Double(n) / 2
        var disk = 0, lit = 0
        for y in 0..<n * 95 / 100 {
            for x in 0..<n {
                let dx = Double(x) + 0.5 - c, dy = Double(y) + 0.5 - c
                guard dx * dx + dy * dy <= r * r else { continue }
                disk += 1
                if pixels[y * n + x] > 16 { lit += 1 }
            }
        }
        return Double(lit) >= 0.95 * Double(disk)
    }

    /// SDO's dated archive for the UTC day of `day`, listing only this channel's frames at `size`.
    public func archiveURL(day: Date, size: Int = 1024) -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let d = calendar.dateComponents([.year, .month, .day], from: day)
        let path = String(format: "%04d/%02d/%02d", d.year!, d.month!, d.day!)
        return URL(string: "https://sdo.gsfc.nasa.gov/assets/img/browse/\(path)/?P=*_\(size)_\(rawValue).jpg")!
    }

    /// This channel's frames named in an archive listing, as `YYYYMMDD_HHMMSS_<size>_<channel>.jpg`, newest first.
    public func frames(inListing html: String, at listing: URL, size: Int = 1024) -> [SolarFrame] {
        let style = Date.ISO8601FormatStyle(dateSeparator: .omitted, timeSeparator: .omitted)
        var frames: [String: SolarFrame] = [:]
        for m in html.matches(of: /(\d{8})_(\d{6})_(\d+)_(\w+)\.jpg/) where m.3 == "\(size)" && m.4 == rawValue {
            guard let time = try? Date("\(m.1)T\(m.2)Z", strategy: style),
                  let url = URL(string: String(m.0), relativeTo: listing)?.absoluteURL else { continue }
            frames[String(m.0)] = SolarFrame(url: url, time: time)
        }
        return frames.values.sorted { $0.time > $1.time }
    }

    /// The newest usable 1024 px frame in the archive for the UTC day of `date`, and the day before when that day
    /// lists fewer than `tries` frames. Downloads at most `tries` frames.
    public func lastUsableFrame(at date: Date = .now, tries: Int = 6, session: URLSession = .shared) async -> (data: Data, time: Date)? {
        var frames: [SolarFrame] = []
        for day in [date, date.addingTimeInterval(-86_400)] where frames.count < tries {
            let listing = archiveURL(day: day)
            guard let (html, _) = try? await session.data(from: listing) else { continue }
            frames += self.frames(inListing: String(decoding: html, as: UTF8.self), at: listing)
        }
        for frame in frames.prefix(tries) {
            if let (data, response) = try? await session.data(from: frame.url),
               (response as? HTTPURLResponse)?.statusCode == 200, isUsable(data) {
                return (data, frame.time)
            }
        }
        return nil
    }
}

/// A frame in SDO's dated archive.
public struct SolarFrame: Sendable, Equatable {
    public var url: URL
    public var time: Date
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

    /// The highest sample in each `interval` of time-ordered samples, for charting: a day of minutes becomes
    /// 288 points and every flare peak keeps its flux and time.
    public static func maxima(_ samples: [XRaySample], every interval: TimeInterval = 300) -> [XRaySample] {
        var out: [XRaySample] = []
        var bin = -Double.infinity
        for s in samples {
            let b = (s.time.timeIntervalSince1970 / interval).rounded(.down)
            if b != bin {
                out.append(s)
                bin = b
            } else if s.flux > out[out.count - 1].flux {
                out[out.count - 1] = s
            }
        }
        return out
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

/// Saved as the feed's grid, one byte per cell in the feed's order (longitude 0...359, then latitude −90...90).
/// Snapshots saved before the grid hold `cells`.
extension Ovation {
    enum CodingKeys: String, CodingKey {
        case forecastTime, grid, cells
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        forecastTime = try c.decode(Date.self, forKey: .forecastTime)
        if let grid = try c.decodeIfPresent(Data.self, forKey: .grid) {
            cells = grid.enumerated().compactMap { i, p in
                p > 0 ? Cell(lon: Double(i / 181), lat: Double(i % 181 - 90), probability: Double(p)) : nil
            }
        } else {
            cells = try c.decode([Cell].self, forKey: .cells)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var grid = Data(count: 360 * 181)
        for cell in cells {
            let lon = Int(cell.lon), lat = Int(cell.lat) + 90
            guard (0..<360).contains(lon), (0...180).contains(lat) else { continue }
            grid[lon * 181 + lat] = UInt8(clamping: Int(cell.probability.rounded()))
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(forecastTime, forKey: .forecastTime)
        try c.encode(grid, forKey: .grid)
    }
}
