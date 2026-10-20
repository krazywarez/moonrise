import Feeds
import SkyEngine
import SwiftUI

/// The next year of eclipses, oppositions, elongations, meteor showers, moon phases and seasons.
struct EventsScreen: View {
    var observer: Observer
    var placeName: String
    /// Cloud forecast, when cloud forecasts are on.
    var forecast: SavedForecast?
    @State private var events: [SkyEvent] = []
    /// Cloud and rating for meteor shower peaks and eclipses within the forecast, by event id.
    @State private var outlooks: [String: Outlook] = [:]
    @State private var filter = "notable"
    @State private var eclipse: SkyEvent?
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    private var shown: [SkyEvent] {
        filter == "all" ? events : events.filter { $0.kind != .moonPhase && $0.kind != .season }
    }

    private var months: [(String, [SkyEvent])] {
        let groups = Dictionary(grouping: shown) { $0.date.formatted(.dateTime.year().month(.wide)) }
        return groups.sorted { $0.value[0].date < $1.value[0].date }.map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    Text("Events").font(.title.weight(.medium))
                    Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 8).padding(.bottom, 12)
                    Text("Eclipses, meteor showers and planets at their best over the next year, as seen \(placeName == "Your location" ? "from where you are" : "from \(placeName)"). Tap a solar eclipse for its path and local times.")
                        .font(.subheadline).foregroundStyle(ink.opacity(0.75))
                    Picker("Show", selection: $filter) {
                        Text("Highlights").tag("notable")
                        Text("Everything").tag("all")
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 16)
                    if let forecast, !outlooks.isEmpty { WeatherCreditLine(saved: forecast).padding(.bottom, 4) }

                    if events.isEmpty {
                        ProgressView().tint(ink).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(months, id: \.0) { month, items in
                        Section {
                            ForEach(items) { e in
                                if e.kind == .solarEclipse {
                                    Button { eclipse = e } label: { row(e, link: true) }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Shows the path and local times")
                                } else {
                                    row(e, link: false)
                                }
                            }
                        } header: {
                            Text(month).font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8)
                                .foregroundStyle(ink.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 20).padding(.bottom, 6)
                                .background(Color.black)
                        }
                    }
                    Text("Meteor shower peaks are typical dates and can shift by a day.")
                        .font(.caption2).foregroundStyle(ink.opacity(0.5)).padding(.vertical, 20)
                }
                .padding(.horizontal, 20)
                .readableWidth()
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $eclipse) { e in EclipseScreen(date: e.date, observer: observer, placeName: placeName) }
        }
        .foregroundStyle(ink)
        .tint(accent)
        .task {
            let observer = observer, forecast = forecast?.forecast
            (events, outlooks) = await Task.detached {
                let events = SkyEngine.events(from: .now, observer: observer)
                var outlooks: [String: Outlook] = [:]
                if let forecast {
                    for e in events { outlooks[e.id] = try? SkyEngine.outlook(for: e, forecast: forecast, observer: observer, now: .now) }
                }
                return (events, outlooks)
            }.value
        }
    }

    private func row(_ e: SkyEvent, link: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(e.date.formatted(.dateTime.day())).font(.title2.weight(.medium).monospacedDigit())
                Text(e.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).textCase(.uppercase).foregroundStyle(ink.opacity(0.6))
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: symbol(e.kind)).font(.subheadline).foregroundStyle(e.visibleHere == true ? accent : ink.opacity(0.7))
                        .accessibilityHidden(true)
                    Text(e.title).font(.body.weight(.medium))
                }
                Text(e.date.formatted(date: .omitted, time: .shortened)).font(.footnote.monospacedDigit()).foregroundStyle(ink.opacity(0.6))
                if !e.detail.isEmpty { Text(e.detail).font(.footnote).foregroundStyle(ink.opacity(0.8)) }
                if let o = outlooks[e.id] { OutlookLine(outlook: o).font(.footnote.monospacedDigit()) }
                if let v = e.visibleHere {
                    HStack(spacing: 5) {
                        Circle().fill(v ? accent : ink.opacity(0.35)).frame(width: 6, height: 6)
                        Text(v ? "Visible from here" : "Not visible from here").font(.caption.weight(.medium))
                            .foregroundStyle(v ? ink : ink.opacity(0.6))
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if link {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(ink.opacity(0.4)).padding(.top, 6)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ k: SkyEvent.Kind) -> String {
        switch k {
        case .moonPhase: "moonphase.full.moon"
        case .lunarEclipse: "moon.circle"
        case .solarEclipse: "sun.max.circle"
        case .opposition: "circle.and.line.horizontal"
        case .elongation: "arrow.left.and.right"
        case .season: "calendar"
        case .meteorShower: "sparkles"
        }
    }
}
