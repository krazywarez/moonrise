import Charts
import SkyRenderer
import SwiftUI

/// The skyline every 10°: drag each bar up to where trees or buildings end in that direction.
struct HorizonEditor: View {
    @AppStorage(SettingsKey.horizonProfile) private var stored = ""
    @State private var profile = HorizonProfile()

    var body: some View {
        Form {
            Section {
                Chart(Array(profile.altitudes.enumerated()), id: \.offset) { i, alt in
                    BarMark(x: .value("Azimuth", Double(i) * HorizonProfile.step + 5), y: .value("Altitude", alt), width: .ratio(0.9))
                }
                .chartXScale(domain: 0...360)
                .chartYScale(domain: 0...60)
                .chartXAxis { AxisMarks(values: [0, 90, 180, 270, 360]) { v in AxisGridLine(); AxisValueLabel(compass(v.as(Double.self) ?? 0)) } }
                .chartYAxis { AxisMarks(values: [0, 15, 30, 45, 60]) { v in AxisGridLine(); AxisValueLabel("\(v.as(Int.self) ?? 0)°") } }
                .chartOverlay { chart in
                    GeometryReader { g in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                                guard let frame = chart.plotFrame.map({ g[$0] }),
                                      let az: Double = chart.value(atX: drag.location.x - frame.minX),
                                      let alt: Double = chart.value(atY: drag.location.y - frame.minY) else { return }
                                let i = min(35, max(0, Int(az / HorizonProfile.step)))
                                profile.altitudes[i] = min(60, max(0, alt.rounded()))
                                stored = profile.stored
                            })
                    }
                }
                .frame(height: 220)
                .accessibilityLabel("Skyline height by direction")
                Button("Clear", role: .destructive) { profile = HorizonProfile(); stored = profile.stored }
                    .disabled(profile.isFlat)
            } footer: {
                Text("Drag along the chart to set how high trees and buildings reach in each direction, from north round through east. The sky chart draws them as ground, so whatever is behind them is hidden.")
            }
        }
        .navigationTitle("Horizon")
        .onAppear { profile = HorizonProfile(stored: stored) ?? HorizonProfile() }
    }

    private func compass(_ az: Double) -> String {
        ["N", "E", "S", "W", "N"][min(4, Int((az / 90).rounded()))]
    }
}
