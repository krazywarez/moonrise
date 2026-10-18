import Library
import SwiftUI

/// Missions in the Library by launch year, from Sputnik to today.
struct ExplorationTimeline: View {
    @State private var selected: LibraryPage?
    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    private var decades: [(Int, [LibraryPage])] {
        let missions = Library.pages(in: .missions).filter { $0.drawing?.launch != nil }.sorted { $0.drawing!.launch! < $1.drawing!.launch! }
        let grouped = Dictionary(grouping: missions) { (Int($0.drawing!.launch!.prefix(4)) ?? 0) / 10 * 10 }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    var body: some View {
        List {
            ForEach(decades, id: \.0) { decade, missions in
                Section("\(String(decade))s") {
                    ForEach(missions) { m in
                        Button { selected = m } label: { row(m) }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.black)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Timeline")
        .foregroundStyle(ink)
        .sheet(item: $selected) { page in NavigationStack { LibraryPageView(page: page) } }
    }

    private func row(_ m: LibraryPage) -> some View {
        let year = String(m.drawing?.launch?.prefix(4) ?? "")
        let active = m.drawing?.status == "active"
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(year).font(.footnote.monospacedDigit()).dimmed(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).font(.body)
                Text(m.subtitle).font(.footnote).dimmed(0.7)
            }
            Spacer()
            if active {
                Circle().fill(accent).frame(width: 7, height: 7).accessibilityLabel("Active")
            }
        }
    }
}
