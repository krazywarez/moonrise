import Foundation
import Testing
@testable import Feeds

@Test func decodesNewsArticles() throws {
    // snapi.json saved from api.spaceflightnewsapi.net/v4/articles/?limit=5 on 2026-10-18.
    let url = try #require(Bundle.module.url(forResource: "Fixtures/snapi", withExtension: "json"))
    let articles = try NewsArticle.decode(Data(contentsOf: url))
    #expect(articles.count == 3)
    #expect(!articles.contains { $0.title.hasPrefix("APOD:") })
    #expect(articles[0].id == 40426)
    #expect(articles[0].site == "Spaceflight Now")
    #expect(articles[0].image?.scheme == "https")
    #expect(articles[0].published == Date(timeIntervalSince1970: 1_792_341_122))
    #expect(!articles[0].summary.hasSuffix(" "))
}

@Test func decodesBackendNews() throws {
    let data = Data(#"{"fetchedAt":"2026-10-22T00:10:00.000Z","results":[{"id":7,"title":"t","summary":" s ","url":"https://example.com/a","image_url":null,"news_site":"ESA","published_at":"2026-10-20T13:00:00Z"}]}"#.utf8)
    let a = try NewsArticle.decode(data)
    #expect(a.map(\.id) == [7])
    #expect(a.first?.summary == "s")
    #expect(a.first?.image == nil)
}
