import Library
import SkyRenderer
import SwiftUI

/// A mission's chapters on the orrery. Moving between chapters runs the clock so the craft travels.
struct StoryScreen: View {
    var story: MissionStory
    @State private var chapter = 0
    @State private var date: Date
    @State private var travel: Task<Void, Never>?

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    init(story: MissionStory) {
        self.story = story
        _date = State(initialValue: story.chapters[0].day)
    }

    var body: some View {
        let c = story.chapters[chapter]
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                OrreryView(date: date, ink: ink, accent: accent, highlight: story.spacecraft)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .accessibilityHidden(true)
                Text(date.formatted(date: .long, time: .omitted)).font(.subheadline.monospacedDigit()).dimmed(0.7)
                Text(c.title).font(.title2.weight(.medium))
                Text(c.text).font(.body).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button { go(to: chapter - 1) } label: { Label("Back", systemImage: "chevron.left") }
                        .disabled(chapter == 0)
                    Spacer()
                    Text("\(chapter + 1) of \(story.chapters.count)").font(.footnote).dimmed(0.6)
                    Spacer()
                    Button { go(to: chapter + 1) } label: { Label("Next", systemImage: "chevron.right").labelStyle(.titleAndIcon) }
                        .disabled(chapter == story.chapters.count - 1)
                }
                .font(.subheadline.weight(.medium))
                .padding(.top, 8)
                Text("Positions: NASA/JPL Horizons.").font(.caption2).dimmed(0.5).padding(.top, 8)
            }
            .padding(20)
            .readableWidth()
        }
        .foregroundStyle(ink)
        .tint(accent)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(story.spacecraft)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { travel?.cancel() }
    }

    /// Moves to chapter `i`, running the date there over about 1.5 s.
    private func go(to i: Int) {
        let from = date, to = story.chapters[i].day
        chapter = i
        travel?.cancel()
        travel = Task {
            let frames = 45
            for f in 1...frames {
                try? await Task.sleep(for: .milliseconds(33))
                if Task.isCancelled { return }
                let t = Double(f) / Double(frames)
                let eased = t * t * (3 - 2 * t)
                date = from.addingTimeInterval(to.timeIntervalSince(from) * eased)
            }
        }
    }
}
