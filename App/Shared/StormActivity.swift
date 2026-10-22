import ActivityKit
import Foundation

/// Live Activity for a geomagnetic storm, updated over the storm's APNs broadcast channel. Shared by the app and
/// the widget extension; `ContentState` matches server/src/storm.ts.
struct StormActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var kp: Double
        /// The higher of `kp` and the forecast for the 3-hour periods now and next.
        var expectedKp: Double
        /// A strongly southward solar wind: Kp usually rises within the hour.
        var early: Bool
        var bz: Double?
        var speed: Double?
        var updated: Date
    }

    var startedAt: Date
}

extension StormActivityAttributes.ContentState {
    /// NOAA G-scale: G1 at Kp 5 through G5 at Kp 9.
    static func scale(_ kp: Double) -> String? {
        kp >= 5 ? "G\(min(Int(kp.rounded(.down)) - 4, 5))" : nil
    }

    var headline: String {
        if let g = Self.scale(kp) { return "\(g) storm, Kp \(kp.formatted(.number.precision(.fractionLength(0...1))))" }
        if let g = Self.scale(expectedKp) { return "\(g) storm expected" }
        return early ? "Storm likely within the hour" : "Kp \(kp.formatted(.number.precision(.fractionLength(0...1))))"
    }
}
