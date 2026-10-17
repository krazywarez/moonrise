import ActivityKit
import Foundation

/// Live Activity for a followed launch. Shared by the app and the widget extension.
struct LaunchActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var net: Date
        /// Launch Library 2 status abbreviation.
        var status: String
    }

    var launchID: String
    var rocket: String
    var mission: String
    var location: String
}
