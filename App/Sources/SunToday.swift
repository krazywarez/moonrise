import Charts
import SkyEngine
import SwiftUI

/// The Sun at the Sky tab's place today: rise and set, day length, noon, golden and blue hours, and its path.
struct SunToday: View {
    var ink: Color
    var accent: Color
    @State private var today: SunDay?
    @State private var yesterday: SunDay?

    private let golden = Color(red: 0.95, green: 0.68, blue: 0.25)
    private let blue = Color(red: 0.35, green: 0.5, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let d = today {
                chart(d)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    row("Sunrise", time(d.sunrise))
                    row("Sunset", time(d.sunset))
                    row("Day length", length(d))
                    row("Solar noon", d.noon.map { "\(time($0)), \(Int((d.noonAltitude ?? 0).rounded()))° up" } ?? "–")
                    row("Golden hour", [d.morningGolden, d.eveningGolden].compactMap { $0 }.map(span).joined(separator: ", ").nonEmpty ?? "–")
                    row("Blue hour", [d.morningBlue, d.eveningBlue].compactMap { $0 }.map(span).joined(separator: ", ").nonEmpty ?? "–")
                }
                .font(.subheadline.monospacedDigit())
                Text("For \(SkyModel.shared.placeName), in this device's time zone. Golden hour: the Sun's centre between 6° above and 4° below the horizon; blue hour: 4° to 6° below.")
                    .font(.caption2).dimmed(0.6)
            } else {
                Text("Loading").font(.footnote).dimmed(0.6)
            }
        }
        .task(id: SkyModel.shared.observer) {
            let o = SkyModel.shared.observer, start = Calendar.current.startOfDay(for: .now)
            let before = Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start
            (today, yesterday) = await Task.detached {
                (try? SunDay(start: start, observer: o), try? SunDay(start: before, observer: o))
            }.value
        }
    }

    private func chart(_ d: SunDay) -> some View {
        Chart {
            RectangleMark(yStart: .value("", -6), yEnd: .value("", -4)).foregroundStyle(blue.opacity(0.25))
            RectangleMark(yStart: .value("", -4), yEnd: .value("", 6)).foregroundStyle(golden.opacity(0.2))
            RuleMark(y: .value("Horizon", 0)).foregroundStyle(ink.opacity(0.4))
            ForEach(d.path, id: \.date) { p in
                LineMark(x: .value("Time", p.date), y: .value("Altitude", p.altitude)).foregroundStyle(ink)
            }
            RuleMark(x: .value("Now", Date.now)).foregroundStyle(accent)
        }
        .chartYScale(domain: -90...90)
        .chartYAxis { AxisMarks(values: [-60, -30, 0, 30, 60]) { v in AxisGridLine().foregroundStyle(ink.opacity(0.12)); AxisValueLabel("\(v.as(Int.self) ?? 0)°").foregroundStyle(ink.opacity(0.6)) } }
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisValueLabel(format: .dateTime.hour()).foregroundStyle(ink.opacity(0.6)) } }
        .frame(height: 140)
        .accessibilityLabel("The Sun's altitude through today")
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow { Text(label).dimmed(0.7); Text(value) }
    }

    private func time(_ d: Date?) -> String { d?.formatted(date: .omitted, time: .shortened) ?? "–" }

    private func span(_ i: DateInterval) -> String { "\(time(i.start))–\(time(i.end))" }

    private func length(_ d: SunDay) -> String {
        guard let l = d.dayLength else { return (d.path.first?.altitude ?? 0) > 0 ? "24 h (the Sun does not set)" : "None (the Sun does not rise)" }
        let h = Int(l) / 3600, m = Int(l) % 3600 / 60
        guard let y = yesterday?.dayLength else { return "\(h) h \(m) min" }
        let change = Int((l - y).rounded())
        return "\(h) h \(m) min, \(change >= 0 ? "+" : "−")\(abs(change) / 60) min \(abs(change) % 60) s on yesterday"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
