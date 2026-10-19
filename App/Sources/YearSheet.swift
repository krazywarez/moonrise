import SwiftUI

/// Picks a year for the historical sky, from 3000 BCE to 3000 CE.
struct YearSheet: View {
    @Binding var year: Int?
    var south = false
    @State private var draft: Int
    @Environment(\.dismiss) private var dismiss

    static let range = -2999...3000

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    private let moments: [(String, Int)] = [
        ("Great Pyramid built, Thuban at the pole", -2559),
        ("Ptolemy's Almagest", 150),
        ("Supernova that made the Crab Nebula", 1054),
        ("Galileo's telescope", 1610),
        ("Apollo 11", 1969),
        ("Polaris closest to the pole", 2100),
    ]

    init(year: Binding<Int?>, south: Bool = false) {
        _year = year
        self.south = south
        _draft = State(initialValue: year.wrappedValue ?? Calendar.current.component(.year, from: .now))
    }

    static func label(_ y: Int) -> String { y > 0 ? "\(y) CE" : "\(1 - y) BCE" }

    private var poleStar: (name: String, degrees: Double)? {
        SkyModel.poleStar(at: SkyModel.date(.now, inYear: draft), south: south)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sky in another year").font(.title.weight(.medium))
                    Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 8).padding(.bottom, 12)
                    Text("Tonight's date and time in any year from 3000 BCE to 3000 CE. The stars drift with precession and their own motion.")
                        .font(.subheadline).foregroundStyle(ink.opacity(0.75))

                    yearPicker.padding(.top, 28)

                    Text("Moments").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8)
                        .foregroundStyle(ink.opacity(0.6)).padding(.top, 32).padding(.bottom, 4)
                    ForEach(moments, id: \.1) { m in moment(m.0, m.1) }

                    Text("Dates before 1582 are in the Julian calendar. Planet positions far from today are approximate.")
                        .font(.caption2).foregroundStyle(ink.opacity(0.5)).padding(.top, 20)
                }
                .padding(20)
                .readableWidth()
            }
            .background(Color.black.ignoresSafeArea())
            .foregroundStyle(ink)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        year = draft == Calendar.current.component(.year, from: .now) ? nil : draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var yearPicker: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(String(draft > 0 ? draft : 1 - draft))
                    .font(.system(size: 64, weight: .light).monospacedDigit())
                    .contentTransition(.numericText())
                Text(draft > 0 ? "CE" : "BCE").font(.subheadline.weight(.medium)).tracking(2).foregroundStyle(ink.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.label(draft))

            if let p = poleStar {
                Text(String(format: "Pole star: %@, %.1f° from the pole", p.name, p.degrees))
                    .font(.footnote).foregroundStyle(ink.opacity(0.75))
            }

            Slider(value: Binding(get: { Double(draft) }, set: { draft = Int($0.rounded()) }), in: Double(Self.range.lowerBound)...Double(Self.range.upperBound))
                .accessibilityLabel("Year")
                .accessibilityValue(Self.label(draft))
            HStack {
                Text("3000 BCE"); Spacer(); Text("1 CE"); Spacer(); Text("3000 CE")
            }
            .font(.caption2).foregroundStyle(ink.opacity(0.5))
            .accessibilityHidden(true)

            HStack(spacing: 8) {
                step("−100", -100); step("−1", -1); step("+1", 1); step("+100", 100)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .animation(.snappy, value: draft)
    }

    private func step(_ title: String, _ by: Int) -> some View {
        Button { draft = min(max(draft + by, Self.range.lowerBound), Self.range.upperBound) } label: {
            Text(title).font(.subheadline.weight(.medium).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(ink.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(by > 0 ? "\(by) years later" : "\(-by) years earlier")
    }

    private func moment(_ title: String, _ y: Int) -> some View {
        Button { draft = y } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(Self.label(y)).font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(draft == y ? accent : ink.opacity(0.7))
                    .frame(width: 84, alignment: .leading)
                Text(title).font(.subheadline)
                Spacer(minLength: 0)
                if draft == y { Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(accent) }
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
