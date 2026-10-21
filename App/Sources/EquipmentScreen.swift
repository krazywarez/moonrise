import Charts
import ObservingLog
import SwiftUI

/// The equipment inventory lives in Documents/Equipment.org, one heading per item.
let equipmentInventory = EquipmentInventory(file: URL.documentsDirectory.appending(path: "Equipment.org"))

extension Equipment {
    /// One line of the specs that apply to this kind, e.g. "203 mm · 1200 mm · f/5.9".
    var specLine: String {
        var parts: [String] = []
        for spec in kind.specs {
            switch spec {
            case .aperture: if let aperture { parts.append("\(Self.format(aperture)) mm aperture") }
            case .focalLength: if let focalLength { parts.append("\(Self.format(focalLength)) mm") }
            case .magnification: if let magnification { parts.append("\(Self.format(magnification))×") }
            case .fieldOfView: if let fieldOfView { parts.append("\(Self.format(fieldOfView))°") }
            case .sensor: if !sensor.isEmpty { parts.append(sensor) }
            }
        }
        if kind == .telescope, let focalRatio { parts.append("f/\(Self.format(focalRatio))") }
        return parts.joined(separator: " · ")
    }

    static func format(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(0...1))) }
}

extension [Equipment] {
    /// Grouped by kind in `Equipment.Kind` order, then by name.
    var byKind: [Equipment] {
        let order = Dictionary(uniqueKeysWithValues: Equipment.Kind.allCases.enumerated().map { ($1, $0) })
        return sorted { order[$0.kind]! != order[$1.kind]! ? order[$0.kind]! < order[$1.kind]! : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct EquipmentScreen: View {
    @State private var items: [Equipment] = []
    @State private var editing: Equipment?

    var body: some View {
        List {
            if items.isEmpty {
                Text("No equipment yet. Add your telescopes, binoculars, eyepieces and other gear, then pick them when you log an observation.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Equipment.Kind.allCases) { kind in
                let group = items.filter { $0.kind == kind && !$0.retired }
                if !group.isEmpty {
                    Section(kind.title) { rows(group) }
                }
            }
            let retired = items.filter(\.retired)
            if !retired.isEmpty {
                Section("Retired") { rows(retired) }
            }
        }
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = Equipment(kind: .telescope, name: "") } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New equipment")
            }
        }
        .sheet(item: $editing) { item in
            EquipmentEditor(item: item) { reload() }
        }
        .onAppear(perform: reload)
    }

    private func rows(_ group: [Equipment]) -> some View {
        ForEach(group) { item in
            NavigationLink { EquipmentDetail(item: item, onChange: reload) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                    let line = item.retired ? [item.kind.title, item.specLine].filter { !$0.isEmpty }.joined(separator: " · ") : item.specLine
                    if !line.isEmpty { Text(line).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .onDelete { idx in
            for i in idx { try? equipmentInventory.delete(id: group[i].id) }
            reload()
        }
    }

    private func reload() { items = equipmentInventory.all().byKind }
}

struct EquipmentDetail: View {
    @State var item: Equipment
    var onChange: () -> Void
    @ObservedObject private var store = observingLogStore
    @State private var names: [String: String] = [:]
    @State private var editing: Equipment?

    private var usage: EquipmentUsage? {
        store.loaded ? EquipmentUsage(of: item.id, in: store.entries, resolver: store.resolver) : nil
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: item.kind.title)
                if !item.specLine.isEmpty { LabeledContent("Specs", value: item.specLine) }
                if item.retired { LabeledContent("Status", value: "Retired") }
                if !item.notes.isEmpty { Text(item.notes).font(.footnote) }
            }
            if let usage { usageSections(usage) }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = item } }
        }
        .sheet(item: $editing) { draft in
            EquipmentEditor(item: draft) {
                if let saved = equipmentInventory.all().first(where: { $0.id == draft.id }) { item = saved }
                onChange()
            }
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder private func usageSections(_ u: EquipmentUsage) -> some View {
        Section("Usage") {
            LabeledContent("Observations", value: "\(u.observations)")
            if let first = u.first { LabeledContent("First used", value: first.formatted(date: .abbreviated, time: .omitted)) }
            if let last = u.last { LabeledContent("Last used", value: last.formatted(date: .abbreviated, time: .omitted)) }
            if u.observations > 0 { LabeledContent("Objects", value: "\(u.distinctObjects)") }
            if let seeing = u.averageSeeing { LabeledContent("Average seeing", value: "\(seeing.formatted(.number.precision(.fractionLength(1)))) of 5") }
        }
        if u.observations > 0 {
            Section("Most observed") {
                ForEach(u.topObjects.prefix(5), id: \.key) { LabeledContent($0.key, value: "\($0.count)") }
            }
            Section("By month") {
                Chart(Array(u.byMonth.enumerated()), id: \.offset) { m, count in
                    BarMark(x: .value("Month", Calendar.current.shortMonthSymbols[m]), y: .value("Observations", count))
                }
                .frame(height: 140)
                .accessibilityLabel("Observations by month")
                ForEach(EquipmentUsage.Season.allCases, id: \.self) { s in
                    LabeledContent(s.title, value: "\(u.bySeason[s] ?? 0)")
                }
            }
            if !u.usedWith.isEmpty {
                Section("Used with") {
                    ForEach(u.usedWith.prefix(5), id: \.key) { LabeledContent(names[$0.key] ?? "Deleted item", value: "\($0.count)") }
                }
            }
        }
    }

    private func reload() {
        names = Dictionary(equipmentInventory.all().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        store.reload()
    }
}

struct EquipmentEditor: View {
    @State var item: Equipment
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $item.kind) {
                        ForEach(Equipment.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Name", text: $item.name)
                }
                if !item.kind.specs.isEmpty {
                    Section("Specs") {
                        ForEach(item.kind.specs, id: \.self) { field($0) }
                        if item.kind == .telescope, let ratio = item.focalRatio {
                            LabeledContent("Focal ratio", value: "f/\(Equipment.format(ratio))")
                        }
                    }
                }
                Section("Notes") {
                    TextEditor(text: $item.notes).frame(minHeight: 100)
                }
                Section {
                    Toggle("Retired", isOn: $item.retired)
                } footer: {
                    Text("Retired items leave the picker but stay on the observations that used them.")
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(item.name.isEmpty ? "New equipment" : item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            item.name = item.name.trimmingCharacters(in: .whitespaces)
                            try equipmentInventory.save(item)
                            onSave()
                            dismiss()
                        } catch {
                            self.error = "Couldn't save: \(error.localizedDescription)"
                        }
                    }
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder private func field(_ spec: Equipment.Spec) -> some View {
        switch spec {
        case .aperture: number("Aperture", unit: "mm", $item.aperture)
        case .focalLength: number("Focal length", unit: "mm", $item.focalLength)
        case .magnification: number(item.kind == .barlow ? "Factor" : "Magnification", unit: "×", $item.magnification)
        case .fieldOfView: number(item.kind == .eyepiece ? "Apparent field" : "Field of view", unit: "°", $item.fieldOfView)
        case .sensor: TextField("Sensor", text: $item.sensor)
        }
    }

    private func number(_ title: String, unit: String, _ value: Binding<Double?>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                NumberField(title: title, value: value)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}

/// Decimal entry that updates its binding on every keystroke, so Save never misses an uncommitted value.
private struct NumberField: View {
    var title: String
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        TextField("", text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(title)
            .onAppear { text = value.map { $0.formatted(.number.grouping(.never)) } ?? "" }
            .onChange(of: text) { value = try? Double(text, format: .number) }
    }
}

/// Multi-select over the inventory for one observation.
struct EquipmentPicker: View {
    @Binding var observation: Observation
    @State private var items: [Equipment] = []
    @State private var adding: Equipment?

    static let nakedEye = "Naked eye"

    /// Free text from an entry logged before the inventory existed.
    private var legacyText: String? {
        observation.equipmentIDs.isEmpty && !observation.equipment.isEmpty && observation.equipment != Self.nakedEye ? observation.equipment : nil
    }

    var body: some View {
        List {
            if let legacyText {
                Section {
                    Text(legacyText)
                } header: {
                    Text("Recorded")
                } footer: {
                    Text("Picking items below replaces this.")
                }
            }
            Section {
                row(Self.nakedEye, selected: observation.equipmentIDs.isEmpty && observation.equipment == Self.nakedEye) {
                    observation.equipmentIDs = []
                    observation.equipment = observation.equipment == Self.nakedEye ? "" : Self.nakedEye
                }
            }
            ForEach(Equipment.Kind.allCases) { kind in
                let group = items.filter { $0.kind == kind && (!$0.retired || observation.equipmentIDs.contains($0.id)) }
                if !group.isEmpty {
                    Section(kind.title) {
                        ForEach(group) { item in
                            row(item.name, detail: item.specLine, selected: observation.equipmentIDs.contains(item.id)) { toggle(item) }
                        }
                    }
                }
            }
            Section {
                Button { adding = Equipment(kind: .telescope, name: "") } label: { Label("Add equipment", systemImage: "plus") }
            }
        }
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $adding) { item in
            EquipmentEditor(item: item) {
                reload()
                if let saved = items.first(where: { $0.id == item.id }) { toggle(saved) }
            }
        }
        .onAppear(perform: reload)
    }

    private func row(_ title: String, detail: String = "", selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                    if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ item: Equipment) {
        var ids = Set(observation.equipmentIDs)
        if ids.contains(item.id) { ids.remove(item.id) } else { ids.insert(item.id) }
        let chosen = items.filter { ids.contains($0.id) }
        observation.equipmentIDs = chosen.map(\.id)
        observation.equipment = chosen.map(\.name).joined(separator: ", ")
    }

    private func reload() { items = equipmentInventory.all().byKind }
}
