import SkyEngine
import SwiftUI

/// Shutter speeds for the partial phases (through the filter) and, for a total eclipse, the features of totality.
struct ExposureGuide: View {
    var total: Bool
    var accent: Color
    @AppStorage("exposureISO") private var iso = 100.0
    @AppStorage("exposureFNumber") private var fNumber = 8.0

    private let isos: [Double] = [100, 200, 400, 800, 1600]
    private let fNumbers: [Double] = [2.8, 4, 5.6, 8, 11, 16]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exposure guide").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
            HStack {
                Picker("ISO", selection: $iso) { ForEach(isos, id: \.self) { Text("ISO \(Int($0))").tag($0) } }
                Picker("Aperture", selection: $fNumber) { ForEach(fNumbers, id: \.self) { Text("f/\($0.formatted())").tag($0) } }
            }
            .pickerStyle(.menu).tint(accent)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(EclipseExposure.partial + (total ? EclipseExposure.totality : [])) { s in
                    GridRow {
                        Text(s.name)
                        Text(EclipseExposure.shutter(fNumber: fNumber, iso: iso, q: s.q) ?? "–").monospacedDigit()
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.footnote)
            Text((total ? "Partial phases through the filter only; the rest in totality, filter off. " : "Filter on the whole time. ") +
                 "Bracket a stop or two either side. " + EclipseExposure.credit)
                .font(.footnote).dimmed(0.7)
        }
    }
}
