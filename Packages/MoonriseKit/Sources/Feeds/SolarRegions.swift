import Foundation

/// NOAA-numbered active regions from SWPC's daily report (json/solar_regions.json), placed on the disk now.
public struct SolarRegion: Sendable, Equatable, Identifiable {
    public var number: Int
    /// Heliographic latitude, degrees, north positive.
    public var latitude: Double
    /// Degrees from the central meridian at `observed`, west positive.
    public var west: Double
    public var observed: Date
    /// Millionths of the hemisphere; nil for plage without spots.
    public var area: Int?
    public var id: Int { number }

    public static let url = URL(string: "https://services.swpc.noaa.gov/json/solar_regions.json")!

    /// Regions in the latest report. SWPC gives longitude east positive. Positions are as of the end of
    /// `observed_date` (24:00 UTC): taken so, they match SDO images; taken at its start, they sit about 13° too far west.
    public static func decode(_ data: Data) throws -> [SolarRegion] {
        struct Row: Decodable { var region: Int; var observed_date: String; var latitude: Double?; var longitude: Double?; var area: Int? }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        guard let latest = rows.map(\.observed_date).max() else { return [] }
        return rows.compactMap { r in
            guard r.observed_date == latest, let lat = r.latitude, let lon = r.longitude,
                  let start = try? Date(r.observed_date + "T00:00:00Z", strategy: .iso8601) else { return nil }
            let day = start.addingTimeInterval(86_400)
            return SolarRegion(number: r.region, latitude: lat, west: -lon, observed: day, area: r.area)
        }
    }

    public static func fetch(session: URLSession = .shared) async throws -> [SolarRegion] {
        try decode(await session.data(from: url).0)
    }

    /// The Sun turns about 13.2° a day as seen from Earth (synodic, at low latitude).
    static let degreesPerDay = 13.2

    /// Position on the disk at `date` in disk radii, x to solar west (right), y to solar north (up);
    /// nil once rotated behind the limb.
    public func disk(at date: Date) -> (x: Double, y: Double)? {
        let r = Double.pi / 180
        let l = (west + date.timeIntervalSince(observed) / 86_400 * Self.degreesPerDay) * r
        let b = latitude * r, b0 = Self.b0(at: date) * r
        guard sin(b) * sin(b0) + cos(b) * cos(l) * cos(b0) > 0 else { return nil }
        return (cos(b) * sin(l), sin(b) * cos(b0) - cos(b) * cos(l) * sin(b0))
    }

    /// Heliographic latitude of the disk centre (B0), degrees: from the Sun's ecliptic longitude and the solar
    /// equator's inclination (7.25°) and node (Meeus, chapter 29, low precision).
    static func b0(at date: Date) -> Double {
        let r = Double.pi / 180
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let d = jd - 2_451_545
        let g = (357.529 + 0.98560028 * d) * r
        let lambda = (280.459 + 0.98564736 * d) * r + (1.915 * sin(g) + 0.020 * sin(2 * g)) * r
        let node = (73.6667 + 1.3958333 * (jd - 2_396_758) / 36_525) * r
        return asin(sin(lambda - node) * sin(7.25 * r)) / r
    }
}
