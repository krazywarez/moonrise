import ActivityKit
import Foundation

/// Live Activity for a meteor shower's peak night. Computed on the device and never updated: the view runs on
/// timers and goes stale at dawn. Shared by the app and the widget extension.
struct MeteorActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}

    var shower: String
    var zhr: Int
    /// The dark part of the night, or the whole night where it never gets fully dark.
    var darkStart: Date
    var darkEnd: Date
    var moonIllumination: Double
}
