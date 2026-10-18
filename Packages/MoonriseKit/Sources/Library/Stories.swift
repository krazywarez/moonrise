import Foundation

/// A mission told in a few dated chapters, shown on the orrery.
public struct MissionStory: Sendable, Decodable, Identifiable {
    public struct Chapter: Sendable, Decodable, Hashable {
        /// UTC date, yyyy-MM-dd.
        public var date: String
        public var title: String
        public var text: String

        public var day: Date { try! Date(date + "T12:00:00Z", strategy: .iso8601) }
    }

    /// Name as in the orrery's spacecraft list.
    public var spacecraft: String
    public var page: String
    public var chapters: [Chapter]
    public var id: String { page }

    public static let all: [MissionStory] = {
        let url = Bundle.module.url(forResource: "stories", withExtension: "json", subdirectory: "stories")!
        return try! JSONDecoder().decode([MissionStory].self, from: Data(contentsOf: url))
    }()

    public static func story(page: String) -> MissionStory? { all.first { $0.page == page } }
}
