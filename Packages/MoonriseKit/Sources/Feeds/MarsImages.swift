import Foundation

/// Latest raw images from the Mars rovers, from NASA's public raw image feeds.
public struct MarsImage: Sendable, Identifiable, Hashable {
    public var id: String
    public var rover: String
    public var sol: Int
    public var camera: String
    public var taken: Date
    public var thumbnail: URL
    public var image: URL
    public var credit: String

    public static let perseveranceURL = URL(string: "https://mars.nasa.gov/rss/api/?feed=raw_images&category=mars2020&feedtype=json&num=100&page=0&order=sol+desc")!
    public static let curiosityURL = URL(string: "https://mars.nasa.gov/api/v1/raw_image_items/?order=sol%20desc,date_taken%20desc&per_page=100&page=0&condition_1=msl:mission")!

    /// Newest full frames from both rovers, `limit` per rover. A rover whose feed fails is left out.
    public static func latest(limit: Int = 12, session: URLSession = .shared) async throws -> [MarsImage] {
        async let p = try? decodePerseverance(await session.data(from: perseveranceURL).0)
        async let c = try? decodeCuriosity(await session.data(from: curiosityURL).0)
        let (pi, ci) = await (p, c)
        guard pi != nil || ci != nil else { throw URLError(.cannotLoadFromNetwork) }
        return Array((pi ?? []).prefix(limit)) + Array((ci ?? []).prefix(limit))
    }

    // MARK: Perseverance

    private struct M2020: Decodable {
        struct Image: Decodable {
            struct Files: Decodable { var medium: URL; var large: URL }
            struct Camera: Decodable { var instrument: String }
            var imageid: String
            var sol: Int
            var sample_type: String
            var date_taken_utc: String
            var image_files: Files
            var camera: Camera
            var credit: String
        }
        var images: [Image]
    }

    static func decodePerseverance(_ data: Data) throws -> [MarsImage] {
        try JSONDecoder().decode(M2020.self, from: data).images
            .filter { $0.sample_type.lowercased() == "full" && $0.camera.instrument != "SKYCAM" && !$0.camera.instrument.hasSuffix("_RIGHT") }
            .compactMap { i in
                guard let taken = parseUTC(i.date_taken_utc) else { return nil }
                return MarsImage(id: i.imageid, rover: "Perseverance", sol: i.sol, camera: cameraName(i.camera.instrument), taken: taken, thumbnail: i.image_files.medium, image: i.image_files.large, credit: i.credit)
            }
            .sorted { $0.taken > $1.taken }
    }

    // MARK: Curiosity

    private struct MSL: Decodable {
        struct Item: Decodable {
            struct Extended: Decodable { var sample_type: String }
            var imageid: String
            var sol: Int
            var instrument: String
            var url: URL
            var date_taken: String
            var extended: Extended
        }
        var items: [Item]
    }

    static func decodeCuriosity(_ data: Data) throws -> [MarsImage] {
        try JSONDecoder().decode(MSL.self, from: data).items
            .filter { $0.extended.sample_type == "full" }
            .compactMap { i in
                guard let taken = parseUTC(i.date_taken) else { return nil }
                return MarsImage(id: i.imageid, rover: "Curiosity", sol: i.sol, camera: cameraName(i.instrument), taken: taken, thumbnail: i.url, image: i.url, credit: "NASA/JPL-Caltech")
            }
            .sorted { $0.taken > $1.taken }
    }

    /// ISO 8601 with or without fractional seconds and zone; a missing zone is UTC.
    static func parseUTC(_ s: String) -> Date? {
        var s = s
        if !s.hasSuffix("Z"), !s.contains("+") { s += "Z" }
        if let d = try? Date(s, strategy: .iso8601) { return d }
        return try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func cameraName(_ code: String) -> String {
        switch code {
        case let c where c.hasPrefix("MCZ"): "Mastcam-Z"
        case let c where c.hasPrefix("NAVCAM"), let c where c.hasPrefix("NAV_"): "Navcam"
        case let c where c.contains("HAZ"): c.hasPrefix("R") ? "Rear Hazcam" : "Front Hazcam"
        case "MAHLI": "MAHLI"
        case let c where c.hasPrefix("MAST"): "Mastcam"
        case "CHEMCAM_RMI": "ChemCam"
        case let c where c.hasPrefix("SHERLOC"): "SHERLOC"
        case let c where c.hasPrefix("SUPERCAM"): "SuperCam"
        default: code
        }
    }
}
