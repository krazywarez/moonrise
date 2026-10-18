import Foundation

/// Space news from the Spaceflight News API (The Space Devs): headline, summary and a link to the article.
public struct NewsArticle: Sendable, Identifiable, Hashable, Decodable {
    public var id: Int
    public var title: String
    public var summary: String
    public var url: URL
    public var image: URL?
    public var site: String
    public var published: Date

    public static let url = URL(string: "https://api.spaceflightnewsapi.net/v4/articles/?limit=40")!

    public static func latest(session: URLSession = .shared) async throws -> [NewsArticle] {
        try decode(await session.data(from: url).0)
    }

    /// Decodes a page, leaving out Astronomy Picture of the Day posts, whose summaries are page navigation.
    static func decode(_ data: Data) throws -> [NewsArticle] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(Page.self, from: data).results.filter { !$0.title.hasPrefix("APOD:") }
    }

    private struct Page: Decodable { var results: [NewsArticle] }

    private enum CodingKeys: String, CodingKey {
        case id, title, summary, url
        case image = "image_url", site = "news_site", published = "published_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary).trimmingCharacters(in: .whitespacesAndNewlines)
        url = try c.decode(URL.self, forKey: .url)
        site = try c.decode(String.self, forKey: .site)
        published = try c.decode(Date.self, forKey: .published)
        // Some sites give http image URLs, which App Transport Security blocks.
        image = (try? c.decodeIfPresent(String.self, forKey: .image)).flatMap { s in
            URL(string: s.hasPrefix("http://") ? "https://" + s.dropFirst(7) : s)
        }
    }
}
