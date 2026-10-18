import SwiftUI

/// Picks a year for the historical sky, from 3000 BCE to 3000 CE.
struct YearSheet: View {
    @Binding var year: Int?
    @State private var draft: Int
    @Environment(\.dismiss) private var dismiss

    static let range = -2999...3000

    private let moments: [(String, Int)] = [
        ("Great Pyramid built, Thuban at the pole", -2559),
        ("Ptolemy's Almagest", 150),
        ("Supernova that made the Crab Nebula", 1054),
        ("Galileo's telescope", 1610),
        ("Apollo 11", 1969),
        ("Polaris closest to the pole", 2100),
    ]

    init(year: Binding<Int?>) {
        _year = year
        _draft = State(initialValue: year.wrappedValue ?? Calendar.current.component(.year, from: .now))
    }

    static func label(_ y: Int) -> String { y > 0 ? "\(y) CE" : "\(1 - y) BCE" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $draft, in: Self.range, step: 100) {
                        Text(Self.label(draft)).font(.title2.monospacedDigit())
                    }
                    Stepper("Year by year", value: $draft, in: Self.range)
                } footer: {
                    Text("Shows the sky for this date and time in another year, with precession and the stars' own motion. Dates before 1582 are in the Julian calendar. Planet positions are approximate far from today.")
                }
                Section("Moments") {
                    ForEach(moments, id: \.1) { m in
                        Button { draft = m.1 } label: {
                            LabeledContent(m.0, value: Self.label(m.1))
                        }
                    }
                }
            }
            .navigationTitle("Sky in another year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        year = draft == Calendar.current.component(.year, from: .now) ? nil : draft
                        dismiss()
                    }
                }
            }
        }
    }
}
