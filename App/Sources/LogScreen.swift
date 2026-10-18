import ObservingLog
import SwiftUI

/// The observing log lives in Documents/Observations, one Org file per entry, visible in the Files app.
let observingLog = ObservingLog(folder: URL.documentsDirectory.appending(path: "Observations"))

struct LogScreen: View {
    @State private var entries: [Observation] = []
    @State private var editing: Observation?
    var newEntry: () -> Observation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
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
                .onDelete { idx in
                    for i in idx { try? observingLog.delete(id: entries[i].id) }
                    reload()
                }
            }
            .navigationTitle("Observing log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
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
                ObservationEditor(observation: o) { reload() }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() { entries = observingLog.all() }
}

struct ObservationEditor: View {
    @State var observation: Observation
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    private static let equipmentChoices = ["Naked eye", "Binoculars", "Telescope", "Camera"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Object", text: $observation.object)
                    DatePicker("Time", selection: $observation.date)
                    TextField("Place", text: $observation.place)
                }
                Section("Conditions") {
                    Picker("Equipment", selection: $observation.equipment) {
                        Text("Not noted").tag("")
                        ForEach(Self.equipmentChoices, id: \.self) { Text($0).tag($0) }
                        if !observation.equipment.isEmpty, !Self.equipmentChoices.contains(observation.equipment) {
                            Text(observation.equipment).tag(observation.equipment)
                        }
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
                        do {
                            try observingLog.save(observation)
                            onSave()
                            dismiss()
                        } catch {
                            self.error = "Couldn't save: \(error.localizedDescription)"
                        }
                    }
                    .disabled(observation.object.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
