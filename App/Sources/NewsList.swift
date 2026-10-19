import Feeds
import SwiftUI

/// Latest space news headlines; tapping one opens the article in Safari.
struct NewsList: View {
    var ink: Color
    var accent: Color
    var reload = 0
    @State private var articles: [NewsArticle]?
    @State private var failed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let articles {
                ForEach(articles) { a in
                    Button { openURL(a.url) } label: { row(a) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the article in Safari")
                }
                Text("Headlines: Spaceflight News API, The Space Devs. Articles belong to their publishers.")
                    .font(.caption2).dimmed(0.5).padding(.vertical, 16)
            } else if failed {
                Text("Couldn't load news. Pull to retry.").font(.footnote).foregroundStyle(accent).padding(.vertical, 12)
            } else {
                ProgressView().tint(ink).padding(.top, 40).frame(maxWidth: .infinity)
            }
        }
        .task(id: reload) { await load(force: reload > 0) }
    }

    /// The API caches for 10 minutes; reuse a fetch from that window unless pulled to refresh.
    func load(force: Bool) async {
        if !force, let cached: [NewsArticle] = FeedMemo.get("news", maxAge: 600) { articles = cached; return }
        do {
            articles = try await NewsArticle.latest()
            if let articles { FeedMemo.set("news", articles) }
            failed = false
        } catch {
            failed = articles == nil
        }
    }

    private func row(_ a: NewsArticle) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(a.site) · \(a.published.formatted(.relative(presentation: .named)))").font(.caption2).dimmed(0.7)
                Text(a.title).font(.headline)
                Text(a.summary).font(.footnote).dimmed(0.8).lineLimit(3)
            }
            Spacer(minLength: 0)
            if let image = a.image {
                RemoteImage(url: image, points: 110) { ink.opacity(0.06) }
                .frame(width: 72, height: 72)
                .clipped()
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.25)).frame(height: 0.5) }
        .contentShape(Rectangle())
    }
}
