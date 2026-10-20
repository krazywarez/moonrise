import Foundation

extension SkyEngine {
    /// Highest point of each fixed J2000 position (degrees) between `start` and `end` while the Sun is below −12°,
    /// sampled every 15 minutes; nil when it doesn't reach `minimumAltitude` in that time.
    public static func bestInDarkness(j2000 coordinates: [(ra: Double, dec: Double)], from start: Date, to end: Date, observer: Observer, minimumAltitude: Double = 25) throws -> [(date: Date, position: Horizontal)?] {
        var best: [(date: Date, position: Horizontal)?] = Array(repeating: nil, count: coordinates.count)
        for s in stride(from: start.timeIntervalSince1970, through: end.timeIntervalSince1970, by: 900).map(Date.init(timeIntervalSince1970:)) {
            guard try horizontal(.sun, at: s, from: observer).altitude < -12 else { continue }
            for (i, h) in horizontal(j2000: coordinates, at: s, from: observer).enumerated()
            where h.altitude >= minimumAltitude && h.altitude > best[i]?.position.altitude ?? -90 {
                best[i] = (s, h)
            }
        }
        return best
    }
}
