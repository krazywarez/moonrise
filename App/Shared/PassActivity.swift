import ActivityKit
import Foundation

/// Live Activity for a satellite pass. Computed on the device and never updated: the view runs on timers
/// and goes stale after set. Shared by the app and the widget extension.
struct PassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}

    var name: String
    var rise: Date
    var peak: Date
    var set: Date
    var riseAzimuth: Double
    var setAzimuth: Double
    var maxAltitude: Double
    var visible: Bool
}
