import Foundation

/// The local skyline: how high trees and buildings reach, every 10° of azimuth from north, in degrees.
public struct HorizonProfile: Sendable, Equatable, Codable {
    public static let step = 10.0
    public var altitudes: [Double]

    public init(altitudes: [Double] = Array(repeating: 0, count: 36)) {
        precondition(altitudes.count == 36)
        self.altitudes = altitudes
    }

    public var isFlat: Bool { altitudes.allSatisfy { $0 <= 0 } }

    /// Linear between the 10° marks.
    public func altitude(at azimuth: Double) -> Double {
        let a = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / Self.step
        let i = Int(a) % 36, f = a - a.rounded(.down)
        return altitudes[i] * (1 - f) + altitudes[(i + 1) % 36] * f
    }

    /// For @AppStorage.
    public var stored: String { altitudes.map { String(Int($0.rounded())) }.joined(separator: ",") }

    public init?(stored: String) {
        let v = stored.split(separator: ",").compactMap { Double($0) }
        guard v.count == 36 else { return nil }
        self.init(altitudes: v)
    }
}
