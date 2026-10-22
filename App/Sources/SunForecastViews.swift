import Charts
import Feeds
import SwiftUI

/// CCOR-2's view of the corona over the last day: the latest frame, and a loop of one frame an hour on request.
struct CoronagraphLoop: View {
    var frames: [SunForecast.Frame]
    var ink: Color
    var accent: Color
    @State private var loop: [(date: Date, image: UIImage)] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loop.isEmpty {
                RemoteImage(url: frames.last?.url, points: 600) { Color.black }
                    .aspectRatio(1024 / 960, contentMode: .fit)
                Button(loading ? "Loading \(frames.count) frames" : "Play the last 24 hours") { Task { await play() } }
                    .disabled(loading).tint(accent).font(.footnote)
            } else {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let i = Int(context.date.timeIntervalSinceReferenceDate * 4) % loop.count
                    VStack(alignment: .leading, spacing: 4) {
                        Image(uiImage: loop[i].image).resizable().aspectRatio(1024 / 960, contentMode: .fit)
                        Text(loop[i].date.formatted(date: .abbreviated, time: .shortened)).font(.caption2.monospacedDigit()).dimmed(0.6)
                    }
                }
            }
        }
        .accessibilityLabel("Coronagraph images of the Sun's outer corona")
    }

    private func play() async {
        loading = true
        var out: [(Date, UIImage)] = []
        for f in frames {
            if let image = try? await ImageLoader.load(f.url, maxPixels: 600) { out.append((f.t, image)) }
        }
        loop = out
        loading = false
    }
}

/// WSA-Enlil's forecast of the solar wind speed at Earth, with CME arrivals shaded.
struct EnlilChart: View {
    var points: [SunForecast.EnlilPoint]
    var ink: Color
    var accent: Color

    var body: some View {
        Chart {
            ForEach(points.filter(\.cloud)) { p in
                RectangleMark(xStart: .value("", p.t), xEnd: .value("", p.t.addingTimeInterval(3600))).foregroundStyle(accent.opacity(0.25))
            }
            ForEach(points) { p in LineMark(x: .value("Time", p.t), y: .value("Speed", p.speed)).foregroundStyle(ink) }
            RuleMark(x: .value("Now", Date.now)).foregroundStyle(ink.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
        }
        .chartYAxis { AxisMarks(values: [300, 500, 700, 900]) { _ in AxisGridLine().foregroundStyle(ink.opacity(0.12)); AxisValueLabel().foregroundStyle(ink.opacity(0.6)) } }
        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisGridLine().foregroundStyle(ink.opacity(0.12)); AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(ink.opacity(0.6)) } }
        .frame(height: 130)
        .accessibilityLabel("Forecast solar wind speed at Earth in kilometres per second")
    }
}

/// Monthly sunspot numbers through cycle 25 and NOAA's prediction with its range.
struct CycleChart: View {
    var cycle: SunForecast.Cycle
    var ink: Color
    var accent: Color

    var body: some View {
        Chart {
            ForEach(cycle.predicted) { p in
                if let d = p.date {
                    AreaMark(x: .value("Month", d), yStart: .value("Low", p.low), yEnd: .value("High", p.high)).foregroundStyle(ink.opacity(0.15))
                    LineMark(x: .value("Month", d), y: .value("Predicted", p.ssn), series: .value("", "predicted"))
                        .foregroundStyle(ink.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            ForEach(cycle.observed) { m in
                if let d = m.date, let s = m.ssn {
                    BarMark(x: .value("Month", d, unit: .month), y: .value("Sunspots", s)).foregroundStyle(ink.opacity(0.35))
                }
                if let d = m.date, let s = m.smoothed {
                    LineMark(x: .value("Month", d), y: .value("Smoothed", s), series: .value("", "smoothed")).foregroundStyle(accent)
                }
            }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .year, count: 2)) { _ in AxisGridLine().foregroundStyle(ink.opacity(0.12)); AxisValueLabel(format: .dateTime.year()).foregroundStyle(ink.opacity(0.6)) } }
        .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(ink.opacity(0.12)); AxisValueLabel().foregroundStyle(ink.opacity(0.6)) } }
        .frame(height: 140)
        .accessibilityLabel("Monthly sunspot numbers in solar cycle 25")
    }
}
