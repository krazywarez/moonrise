import ObservingLog
import SwiftUI

/// The observing log lives in Documents/Observations, one Org file per entry, visible in the Files app.
let observingLog = ObservingLog(folder: URL.documentsDirectory.appending(path: "Observations"))

@MainActor let observingLogStore = ObservingLogStore(log: observingLog)

/// The parsed log and programs, shared by the log screens. Files are read off the main thread. Screens call
/// `reload` when they appear, so files changed in the Files app are picked up.
@MainActor final class ObservingLogStore: ObservableObject {
    struct Snapshot: Sendable {
        var entries: [Observation]
        var programs: [ObservingProgram]
        var resolver: CatalogResolver
        var progress: [String: ProgramProgress]
    }

    /// Newest first.
    @Published private(set) var entries: [Observation] = []
    /// Messier, then the files in the Programs folder.
    @Published private(set) var programs: [ObservingProgram] = []
    @Published private(set) var resolver = CatalogResolver()
    /// By program ID.
    @Published private(set) var progress: [String: ProgramProgress] = [:]
    /// False until the first read finishes.
    @Published private(set) var loaded = false
    private let log: ObservingLog
    /// Results of reads started before the latest reload or delete are dropped.
    private var generation = 0
    /// The read the published values were last set from.
    private var shown: Snapshot?

    init(log: ObservingLog) { self.log = log }

    func reload() {
        generation += 1
        let g = generation, log = log
        Task {
            let s = await Task.detached(priority: .userInitiated) { ObservingLogStore.read(log) }.value
            guard g == generation, s.entries != shown?.entries || s.programs != shown?.programs else { return }
            shown = s
            entries = s.entries
            programs = s.programs
            resolver = s.resolver
            progress = s.progress
            loaded = true
        }
    }

    /// Writes as `ObservingLog.save`, with names resolved against the current programs, then reloads.
    func save(_ o: Observation) async throws {
        let log = log
        try await Task.detached(priority: .userInitiated) { try log.save(o, resolver: CatalogResolver(programs: log.programs())) }.value
        reload()
    }

    /// Removes the entries from `entries` at once, then deletes their files and reloads.
    func delete(ids: [String]) {
        entries.removeAll { ids.contains($0.id) }
        generation += 1
        let log = log
        Task {
            await Task.detached(priority: .userInitiated) { for id in ids { try? log.delete(id: id) } }.value
            reload()
        }
    }

    nonisolated private static func read(_ log: ObservingLog) -> Snapshot {
        let programs = log.programs()
        let resolver = CatalogResolver(programs: programs)
        let entries = log.all()
        let index = LogIndex(log: entries, resolver: resolver)
        let progress = Dictionary(programs.map { ($0.id, ProgramProgress(program: $0, index: index)) }, uniquingKeysWith: { a, _ in a })
        return Snapshot(entries: entries, programs: programs, resolver: resolver, progress: progress)
    }
}

struct LogScreen: View {
    @ObservedObject private var store = observingLogStore
    @State private var editing: Observation?
    var newEntry: () -> Observation
    @Environment(\.dismiss) private var dismiss

    private var entries: [Observation] { store.entries }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Programs") { ProgramsScreen(newEntry: newEntry) }
                if store.loaded, entries.isEmpty {
                    Text("No observations yet. Add one here, or use Log on an object's card in the Sky tab.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(entries) { o in
                    Button { editing = o } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(o.object).font(.body)
                            Text("\(o.date.formatted(date: .abbreviated, time: .shortened)) · \(o.place)").font(.footnote).foregroundStyle(.secondary)
                            if !o.notes.isEmpty { Text(o.notes).font(.footnote).lineLimit(3) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { idx in store.delete(ids: idx.map { entries[$0].id }) }
            }
            .navigationTitle("Observing log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { EquipmentScreen() } label: { Image(systemName: "binoculars") }
                        .accessibilityLabel("Equipment")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = newEntry() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New observation")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Saved as Org files in Files › On My iPhone › Moonrise › Observations.")
                    .font(.caption2).foregroundStyle(.secondary).padding(8)
            }
            .sheet(item: $editing) { o in
                ObservationEditor(observation: o)
            }
        }
        .onAppear { store.reload() }
    }
}

struct ObservationEditor: View {
    @State var observation: Observation
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var names: [String: String] = [:]

    /// Current inventory names for linked items, else the text stored with the entry.
    private var equipmentSummary: String {
        let current = observation.equipmentIDs.compactMap { names[$0] }
        if !current.isEmpty, current.count == observation.equipmentIDs.count { return current.joined(separator: ", ") }
        return observation.equipment.isEmpty ? "Not noted" : observation.equipment
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Object", text: $observation.object)
                    DatePicker("Time", selection: $observation.date)
                    TextField("Place", text: $observation.place)
                }
                Section("Conditions") {
                    NavigationLink { EquipmentPicker(observation: $observation) } label: {
                        LabeledContent("Equipment", value: equipmentSummary)
                    }
                    Picker("Seeing", selection: $observation.seeing) {
                        Text("Not noted").tag(Int?.none)
                        ForEach(1...5, id: \.self) { Text("\($0) of 5").tag(Int?.some($0)) }
                    }
                }
                Section("Notes") {
                    TextEditor(text: $observation.notes).frame(minHeight: 140)
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(observation.object.isEmpty ? "New observation" : observation.object)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await observingLogStore.save(observation)
                                dismiss()
                            } catch {
                                self.error = "Couldn't save: \(error.localizedDescription)"
                            }
                        }
                    }
                    .disabled(observation.object.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                names = Dictionary(equipmentInventory.all().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            }
        }
    }
}
