import Foundation

/// The NOAA feeds behind the Sun tab, saved after each complete load so the tab has something to show offline.
public struct SunSnapshot: Sendable, Equatable, Codable {
    public var fetched: Date
    public var kp: [KpBar]
    public var xray: [XRaySample]
    public var ovation: Ovation?
    public var scales: NOAAScales?
    public var probabilities: SolarProbabilities?

    public init(fetched: Date, kp: [KpBar], xray: [XRaySample], ovation: Ovation?, scales: NOAAScales?, probabilities: SolarProbabilities?) {
        self.fetched = fetched
        self.kp = kp
        self.xray = xray
        self.ovation = ovation
        self.scales = scales
        self.probabilities = probabilities
    }

    public func save(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }

    public static func load(from file: URL) -> SunSnapshot? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(SunSnapshot.self, from: $0) }
    }
}
