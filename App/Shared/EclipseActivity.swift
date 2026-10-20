import ActivityKit
import Foundation

/// Live Activity for eclipse contacts at one site. Everything is fixed at the start and drawn with
/// timer text, so it counts down correctly without updates. Shared by the app and the widget extension.
struct EclipseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}

    /// "Total", "Annular" or "Partial".
    var kind: String
    var site: String
    var c1: Date
    var c2: Date?
    var peak: Date
    var c3: Date?
    var c4: Date
    /// Time zone identifier at the site; clock times are in UTC without one.
    var timeZone: String?
}
