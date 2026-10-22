import Charts
import SkyEngine
import SwiftUI

/// Average cloud near an eclipse date, from MODIS Terra's morning pass (about 10:30 local time), 2015–2024:
/// Clouds/clouds-MMDD.bin, 360 × 180 bytes, rows from 90° N, columns from 180° W, percent or 255 for no data.
/// Made by scripts/make-clouds.py.
enum CloudClimatology {
    static func grid(for date: Date) -> Data? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let d = calendar.dateComponents([.month, .day], from: date)
        let name = String(format: "clouds-%02d%02d", d.month ?? 0, d.day ?? 0)
        return Bundle.main.url(forResource: name, withExtension: "bin", subdirectory: "Clouds").flatMap { try? Data(contentsOf: $0) }
    }

    static func percent(_ grid: Data, latitude: Double, longitude: Double) -> Int? {
        let row = min(179, max(0, Int((90 - latitude).rounded(.down))))
        let col = min(359, max(0, Int((longitude + 180).rounded(.down))))
        let v = grid[grid.startIndex + row * 360 + col]
        return v == 255 ? nil : Int(v)
    }
}

/// Typical cloud at the site and along the centre line, for the eclipse's date.
struct EclipseClouds: View {
    var path: EclipsePath
    var site: Observer
    var ink: Color
    var accent: Color

    var body: some View {
        if let grid = CloudClimatology.grid(for: path.peak) {
            let line = path.points.compactMap { p in
                CloudClimatology.percent(grid, latitude: p.center.lat, longitude: p.center.lon).map { (lon: p.center.lon, cloud: $0) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Cloud on this date").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
                if let here = CloudClimatology.percent(grid, latitude: site.latitude, longitude: site.longitude) {
                    Text("About \(here)% cloud here on a typical morning around this date.").font(.subheadline)
                }
                Chart(line, id: \.lon) { p in
                    LineMark(x: .value("Longitude", p.lon), y: .value("Cloud", p.cloud)).foregroundStyle(ink)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in AxisGridLine().foregroundStyle(ink.opacity(0.15)); AxisValueLabel("\(v.as(Int.self) ?? 0)%") } }
                .chartXAxis { AxisMarks { v in AxisValueLabel("\(Int(v.as(Double.self) ?? 0))°") } }
                .frame(height: 120)
                .accessibilityLabel("Typical cloud cover along the centre line by longitude")
                Text("Along the centre line, by longitude. Mean MODIS Terra cloud fraction at about 10:30 local time, within six days of this date, 2015–2024. Data: NASA GIBS.")
                    .font(.footnote).dimmed(0.7)
            }
        }
    }
}
