import ObservingLog
import SkyEngine
import SwiftUI

/// Observing programs: the bundled Messier list plus Org files in Documents/Observations/Programs.
struct ProgramsScreen: View {
    var newEntry: () -> Observation
    @ObservedObject private var store = observingLogStore

    var body: some View {
        List {
            Section {
                ForEach(store.programs) { p in
                    let n = store.progress[p.id]?.count ?? 0
                    NavigationLink { ProgramDetail(program: p, newEntry: newEntry) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(p.title)
                                Spacer()
                                Text("\(n) / \(p.objects.count)").monospacedDigit().foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(n), total: Double(max(p.objects.count, 1)))
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel("\(p.title), \(n) of \(p.objects.count) logged")
                }
            } footer: {
                Text("Add your own lists as Org files in Files › On My iPhone › Moonrise › Observations › Programs: a #+TITLE: line, then one top-level heading per object, such as * M13 or * NGC 869. A :CATALOG: property sets an object's IDs, and :RA: and :DEC: in degrees its position.")
            }
        }
        .navigationTitle("Programs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let folder = observingLog.programsFolder
            Task.detached { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            store.reload()
        }
    }
}

struct ProgramDetail: View {
    struct Candidate: Sendable {
        var object: ObservingProgram.Object
        var best: Date
        var position: Horizontal
    }

    var program: ObservingProgram
    var newEntry: () -> Observation
    @ObservedObject private var store = observingLogStore
    @State private var upTonight: [Candidate]?
    @State private var editing: Observation?

    private var progress: ProgramProgress? { store.progress[program.id] }

    var body: some View {
        List {
            Section {
                if let upTonight {
                    let pending = upTonight.filter { progress?.first[$0.object.id] == nil }
                    if pending.isEmpty {
                        Text("None of the objects still to log gets 25° up in full darkness tonight.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(Array(pending.enumerated()), id: \.offset) { _, c in
                        row(c.object, trailing: "\(c.best.formatted(date: .omitted, time: .shortened)) · \(Int(c.position.altitude.rounded()))° \(SkyEngine.compass(c.position.azimuth))")
                    }
                } else {
                    ProgressView()
                }
            } header: {
                Text("Not yet logged, up tonight")
            } footer: {
                Text("Best time while the Sun is more than 12° below the horizon.")
            }
            Section("\(progress?.count ?? 0) of \(program.objects.count) logged") {
                ForEach(Array(program.objects.enumerated()), id: \.offset) { _, o in
                    row(o, trailing: progress?.first[o.id].map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "Log")
                }
            }
        }
        .navigationTitle(program.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { o in
            ObservationEditor(observation: o)
        }
        .onAppear { store.reload() }
        .task { await findUpTonight() }
    }

    /// Opens the first entry for a logged object, else a new entry for it.
    private func row(_ o: ObservingProgram.Object, trailing: String) -> some View {
        let logged = progress?.first[o.id]
        return Button {
            if let logged {
                editing = logged
            } else {
                var entry = newEntry()
                entry.object = o.name
                entry.catalog = o.ids
                editing = entry
            }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.name)
                    if !o.detail.isEmpty { Text(o.detail).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(trailing).font(.footnote).monospacedDigit().foregroundStyle(logged == nil ? .primary : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(logged == nil ? "Logs this object" : "Opens the entry")
    }

    private func findUpTonight() async {
        let here = newEntry()
        guard let lat = here.latitude, let lon = here.longitude else { upTonight = []; return }
        let observer = Observer(latitude: lat, longitude: lon)
        let pending = program.objects.filter { progress?.first[$0.id] == nil && $0.ra != nil && $0.dec != nil }
        let found = await Task.detached {
            guard let night = try? Tonight(at: .now, from: observer),
                  let best = try? SkyEngine.bestInDarkness(j2000: pending.map { ($0.ra!, $0.dec!) }, from: night.start, to: night.end, observer: observer)
            else { return [Candidate]() }
            return zip(pending, best).compactMap { o, b in b.map { Candidate(object: o, best: $0.date, position: $0.position) } }
        }.value
        upTonight = found.sorted { $0.best < $1.best }
    }
}
