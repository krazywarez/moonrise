import ActivityKit
import SwiftUI
import WidgetKit

struct EclipseLiveActivity: Widget {
    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EclipseActivityAttributes.self) { context in
            EclipseActivityView(attributes: context.attributes, ink: ink, accent: accent)
                .foregroundStyle(ink)
                .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            let a = context.attributes
            let next = a.c2 ?? a.peak
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(a.kind) eclipse").font(.system(size: 14, weight: .medium))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(to: next).font(.system(size: 14).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let c2 = a.c2, let c3 = a.c3 {
                        HStack {
                            Text(a.site)
                            Spacer()
                            Text("\(clock(c2, a))–\(clock(c3, a))")
                        }
                        .font(.system(size: 12).monospacedDigit()).opacity(0.8)
                    } else {
                        Text("\(a.site) · maximum \(clock(a.peak, a))").font(.system(size: 12).monospacedDigit()).opacity(0.8)
                    }
                }
            } compactLeading: {
                IslandWidth {
                    Text(a.c2 == nil ? "Max" : "C2").font(.system(size: 12, weight: .medium))
                } limited: {
                    Image(systemName: "sun.max")
                }
            } compactTrailing: {
                countdown(to: next).font(.system(size: 12).monospacedDigit()).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "sun.max")
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct EclipseActivityView: View {
    @Environment(\.activityFamily) private var family
    var attributes: EclipseActivityAttributes
    var ink: Color
    var accent: Color

    private var a: EclipseActivityAttributes { attributes }

    var body: some View {
        if family == .small { small } else { medium }
    }

    /// Apple Watch Smart Stack and CarPlay.
    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(a.kind) eclipse").font(.system(size: 13, weight: .medium)).lineLimit(1)
            HStack(spacing: 4) {
                Text(a.c2 == nil ? "Max" : "C2")
                countdown(to: a.c2 ?? a.peak)
            }
            .font(.system(size: 17, weight: .medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(a.kind) eclipse · \(a.site)").font(.system(size: 15, weight: .medium))
            HStack(alignment: .firstTextBaseline) {
                if let c2 = a.c2, let c3 = a.c3 {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(a.kind == "Total" ? "Totality in" : "Annularity in").font(.system(size: 12)).opacity(0.7)
                        countdown(to: c2).font(.system(size: 34, weight: .medium).monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Lasts").font(.system(size: 12)).opacity(0.7)
                        Text(timerInterval: c2...c3, countsDown: true).font(.system(size: 34, weight: .medium).monospacedDigit())
                            .foregroundStyle(accent).multilineTextAlignment(.trailing)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Maximum in").font(.system(size: 12)).opacity(0.7)
                        countdown(to: a.peak).font(.system(size: 34, weight: .medium).monospacedDigit())
                    }
                }
            }
            ProgressView(timerInterval: a.c1...a.c4, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .tint(ink)
            HStack {
                ForEach(contacts(a), id: \.0) { name, date in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name).font(.system(size: 10)).opacity(0.6)
                        Text(clock(date, a)).font(.system(size: 11).monospacedDigit())
                    }
                    if name != "C4" { Spacer(minLength: 4) }
                }
            }
            Text(a.timeZone == nil ? "Times in UTC" : "Local time at the site").font(.system(size: 10)).opacity(0.6)
        }
        .padding(16)
    }
}

/// Counts down to `date` and then stays at zero.
private func countdown(to date: Date) -> Text {
    Text(timerInterval: date.addingTimeInterval(-86_400)...date, countsDown: true)
}

private func contacts(_ a: EclipseActivityAttributes) -> [(String, Date)] {
    [("C1", a.c1), ("C2", a.c2), ("Max", a.c2 == nil ? a.peak : nil), ("C3", a.c3), ("C4", a.c4)].compactMap { n, d in d.map { (n, $0) } }
}

/// A string: Text(_:format:) would replace the style's time zone with the environment's.
private func clock(_ date: Date, _ a: EclipseActivityAttributes) -> String {
    date.formatted(Date.FormatStyle(date: .omitted, time: .standard, timeZone: a.timeZone.flatMap(TimeZone.init(identifier:)) ?? .gmt))
}
