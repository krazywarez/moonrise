import Library
import SkyRenderer
import SwiftUI

struct SystemScreen: View {
    /// Days from now shown by the slider.
    @State private var offsetDays = 0.0
    @State private var playing = false
    @State private var libraryPage: LibraryPage?
    @Environment(\.dynamicTypeSize) private var typeSize

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)
    private let background = Color.black

    private static let start = Date(timeIntervalSince1970: -378_691_200) // 1958-01-01
    private static let end = Date(timeIntervalSince1970: 2_524_608_000) // 2050-01-01
    private var range: ClosedRange<Double> {
        (Self.start.timeIntervalSinceNow / 86_400)...(Self.end.timeIntervalSinceNow / 86_400)
    }
    private var date: Date { .now.addingTimeInterval(offsetDays * 86_400) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Solar system").font(.title.weight(.medium))
                Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 8).padding(.bottom, 16)

                // Labels in this dense diagram stop growing at xxLarge; the table below scales fully.
                OrreryView(date: date, ink: ink, accent: accent)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .accessibilityElement()
                    .accessibilityLabel("Orrery for \(date.formatted(.dateTime.year().month(.wide))). Planets and spacecraft distances are listed below.")

                HStack(spacing: 12) {
                    Button { playing.toggle() } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(playing ? "Pause" : "Play")
                    Text(date.formatted(.dateTime.year().month(.abbreviated)))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .fixedSize()
                    Slider(value: $offsetDays, in: range).tint(ink)
                    Button { playing = false; offsetDays = 0 } label: {
                        Text("Today").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .font(.footnote.weight(.medium))
                    .opacity(abs(offsetDays) < 1 ? 0.6 : 1)
                }
                .padding(.top, 12)

                Text("Distances beyond 1 AU are drawn on a logarithmic scale. Rings: planet orbits, then 50, 100 and 200 AU.")
                    .font(.caption2).dimmed(0.6).padding(.top, 8)

                section("Spacecraft") {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Spacecraft.all) { craft in
                                VStack(alignment: .leading, spacing: 2) {
                                    craftName(craft)
                                    Text(craftDistance(craft)).monospacedDigit().dimmed(0.7)
                                }
                                .font(.subheadline)
                            }
                        }
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("").gridColumnAlignment(.leading)
                                Text("From Sun").dimmed(0.6)
                                Text("Light time").dimmed(0.6)
                            }
                            .font(.caption2)
                            ForEach(Spacecraft.all) { craft in
                                GridRow {
                                    craftName(craft)
                                    if let d = craft.distance(at: date) {
                                        Text(String(format: "%.1f AU", d)).monospacedDigit()
                                        Text(lightTime(au: d)).monospacedDigit()
                                    } else {
                                        Text("launch \(craft.launch.prefix(4))").dimmed(0.5)
                                        Text("")
                                    }
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
                DSNSection(ink: ink, accent: accent).padding(.top, 24)
                MarsSection().padding(.top, 24)
                Text("Spacecraft positions: NASA/JPL Horizons. Pioneer 10 and 11 positions after contact was lost are predictions.")
                    .font(.caption2).dimmed(0.5).padding(.vertical, 16)
            }
            .padding(.horizontal, 20)
            .readableWidth()
        }
        .foregroundStyle(ink)
        .background(background.ignoresSafeArea())
        .sheet(item: $libraryPage) { page in
            NavigationStack { LibraryPageView(page: page) }
        }
        .task(id: playing) {
            while playing && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                offsetDays = min(offsetDays + 30, range.upperBound)
                if offsetDays >= range.upperBound { playing = false }
            }
        }
    }

    @ViewBuilder
    private func craftName(_ craft: Spacecraft) -> some View {
        if let page = Library.page(spacecraft: craft.name) {
            Button { libraryPage = page } label: { Text(craft.name).underline().frame(minHeight: 44, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
        } else {
            Text(craft.name)
        }
    }

    private func craftDistance(_ craft: Spacecraft) -> String {
        guard let d = craft.distance(at: date) else { return "launch \(craft.launch.prefix(4))" }
        return String(format: "%.1f AU from the Sun · light time %@", d, lightTime(au: d))
    }

    /// One-way light time from the Sun's distance, as hours and minutes.
    private func lightTime(au: Double) -> String {
        let seconds = au * 499.004784
        let h = Int(seconds / 3600), m = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "\(h) h \(m) m" : "\(m) m"
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            content()
        }
        .padding(.top, 24)
    }
}
