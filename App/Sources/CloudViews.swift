import Feeds
import SkyEngine
import SwiftUI

/// The rating word, set like a section label, then its reason: "GO  Clear 22:00–4:00".
struct OutlookLine: View {
    var outlook: Outlook

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let r = outlook.rating {
                Text(r.rawValue).font(.caption.weight(.semibold)).textCase(.uppercase).tracking(0.8)
            }
            Text(outlook.reason)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hourly high, mid and low cloud across `window`, darker for more cover, with the Moon's time up drawn beneath.
struct CloudStrip: View {
    var forecast: CloudForecast
    var window: DateInterval
    var moonUp: [DateInterval]
    var ink: Color
    private let row: CGFloat = 12

    private var parts: [(hour: HourSample, span: DateInterval)] {
        forecast.hours.compactMap { h in
            guard let span = DateInterval(start: h.date, duration: 3600).intersection(with: window), span.duration > 0 else { return nil }
            return (h, span)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(["High", "Mid", "Low", "Moon"], id: \.self) { Text($0).frame(height: row) }
            }
            .font(.caption2).dimmed(0.6)
            VStack(spacing: 2) {
                Canvas { context, size in
                    let x = { (d: Date) in CGFloat(d.timeIntervalSince(window.start) / window.duration) * size.width }
                    for (i, cover) in [\HourSample.cloudHigh, \.cloudMid, \.cloudLow].enumerated() {
                        let y = CGFloat(i) * row + 2
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: row - 4)), with: .color(ink.opacity(0.1)))
                        for p in parts {
                            let r = CGRect(x: x(p.span.start), y: y, width: x(p.span.end) - x(p.span.start), height: row - 4)
                            context.fill(Path(r), with: .color(ink.opacity(p.hour[keyPath: cover])))
                        }
                    }
                    for p in parts where p.hour.date > window.start {
                        context.fill(Path(CGRect(x: x(p.hour.date), y: 0, width: 0.5, height: 3 * row)), with: .color(ink.opacity(0.4)))
                    }
                    for m in moonUp {
                        guard let up = m.intersection(with: window), up.duration > 0 else { continue }
                        context.fill(Path(CGRect(x: x(up.start), y: 3.5 * row - 0.5, width: x(up.end) - x(up.start), height: 1)), with: .color(ink))
                    }
                }
                .frame(height: 4 * row)
                HStack {
                    Text(time(window.start))
                    Spacer()
                    Text(time(window.end))
                }
                .font(.caption2.monospacedDigit()).dimmed(0.6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cloud by hour")
        .accessibilityValue(parts.map { p in
            "\(time(p.span.start)): low \(percent(p.hour.cloudLow)), mid \(percent(p.hour.cloudMid)), high \(percent(p.hour.cloudHigh))"
        }.joined(separator: "; "))
    }

    private func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    private func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
}

/// The Apple Weather mark and legal link that must accompany forecast data, with the time of the forecast.
struct WeatherCreditLine: View {
    var saved: SavedForecast

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                AsyncImage(url: saved.credit.markURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text("\u{F8FF}Weather").font(.caption2)
                }
                .frame(height: 12)
                .accessibilityLabel("Apple Weather")
                Link("Other data sources", destination: saved.credit.legalURL).font(.caption2).underline()
            }
            Text("Cloud forecast from \(saved.forecast.fetched.formatted(Calendar.current.isDateInToday(saved.forecast.fetched) ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute())).")
                .font(.caption2).dimmed(0.6)
        }
    }
}
