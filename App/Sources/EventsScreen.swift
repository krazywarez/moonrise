import SkyEngine
import SwiftUI

/// The next year of eclipses, oppositions, elongations, meteor showers, moon phases and seasons.
struct EventsScreen: View {
    var observer: Observer
    var placeName: String
    @State private var events: [SkyEvent] = []
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
            List {
                Section {
                    Picker("Show", selection: $filter) {
                        Text("Notable").tag("notable")
                        Text("Everything").tag("all")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Visibility is for \(placeName). Meteor shower peaks are typical dates and can shift by a day.")
                }
                if events.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
                ForEach(months, id: \.0) { month, items in
                    Section(month) {
                        ForEach(items) { e in
                            if e.kind == .solarEclipse {
                                Button { eclipse = e } label: { row(e) }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Shows the path and local times")
                            } else {
                                row(e)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $eclipse) { e in EclipseScreen(date: e.date, observer: observer, placeName: placeName) }
        }
        .foregroundStyle(ink)
        .task {
            let observer = observer
            events = await Task.detached { SkyEngine.events(from: .now, observer: observer) }.value
        }
    }

    private func row(_ e: SkyEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol(e.kind)).frame(width: 22).dimmed(0.8).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title).font(.body)
                Text(e.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.footnote.monospacedDigit()).dimmed(0.7)
                if !e.detail.isEmpty { Text(e.detail).font(.footnote).dimmed(0.8) }
                if let v = e.visibleHere {
                    Text(v ? "Visible from here" : "Not visible from here")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(v ? ink : ink.opacity(0.7))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(v ? accent : ink.opacity(0.4), lineWidth: 1))
                }
            }
        }
        .padding(.vertical, 4)
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
