import ActivityKit
import Foundation

/// Live Activity for a mission covered live. Shared by the app and the widget extension.
struct EventActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var next: String?
        var nextAt: Date?
        var distanceKm: Double
    }

    var eventID: String
    var title: String
    var launch: Date
}
