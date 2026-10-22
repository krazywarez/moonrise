import ActivityKit
import SwiftUI
import WidgetKit

struct MeteorLiveActivity: Widget {
    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeteorActivityAttributes.self) { context in
            MeteorActivityView(context: context, ink: ink)
                .foregroundStyle(ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.shower).font(.system(size: 14, weight: .medium)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.attributes).font(.system(size: 14, weight: .medium).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary(context.attributes)).font(.system(size: 12)).lineLimit(1).opacity(0.8)
                        darkProgress(context.attributes, ink: ink)
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                countdown(context.attributes).font(.system(size: 12).monospacedDigit())
            } minimal: {
                Image(systemName: "sparkles")
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

private func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

/// To dark, then the dark time left.
private func countdown(_ m: MeteorActivityAttributes) -> Text {
    liveTimer(m.darkStart > .now ? m.darkStart : m.darkEnd)
}

private func summary(_ m: MeteorActivityAttributes) -> String {
    "Up to \(m.zhr) an hour · dark \(time(m.darkStart))–\(time(m.darkEnd)) · Moon \(Int((m.moonIllumination * 100).rounded()))%"
}

private func darkProgress(_ m: MeteorActivityAttributes, ink: Color) -> some View {
    ProgressView(timerInterval: m.darkStart...m.darkEnd, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
        .tint(ink)
}

private struct MeteorActivityView: View {
    @Environment(\.activityFamily) private var family
    @Environment(\.isActivityFullscreen) private var fullscreen
    var context: ActivityViewContext<MeteorActivityAttributes>
    var ink: Color

    private var m: MeteorActivityAttributes { context.attributes }

    var body: some View {
        Group {
            if family == .small { small } else { medium }
        }
        // StandBy: black, to blend with the clock face.
        .activityBackgroundTint(fullscreen ? .black : Color(red: 0.043, green: 0.078, blue: 0.141))
    }

    /// Apple Watch Smart Stack and CarPlay.
    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(m.shower).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if context.isStale {
                Text("Dawn \(time(m.darkEnd))").font(.system(size: 13).monospacedDigit()).opacity(0.8)
            } else {
                countdown(m).font(.system(size: 17, weight: .medium).monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(m.shower) peak").font(.system(size: 11, weight: .medium)).textCase(.uppercase).tracking(0.6).opacity(0.8)
                Spacer()
                if !context.isStale {
                    Text(m.darkStart > .now ? "dark in" : "dark for").font(.system(size: 11)).opacity(0.7)
                    countdown(m).font(.system(size: 17, weight: .medium).monospacedDigit()).frame(minWidth: 60, alignment: .trailing)
                }
            }
            Text(summary(m)).font(.system(size: 13)).lineLimit(1)
            if context.isStale {
                Text("Over at dawn, \(time(m.darkEnd))").font(.system(size: 12)).opacity(0.8)
            } else {
                darkProgress(m, ink: ink)
            }
        }
        .padding(16)
    }
}

#if DEBUG
#Preview("Lock Screen", as: .content, using: MeteorActivityAttributes(shower: "Orionids", zhr: 20, darkStart: .now.addingTimeInterval(-3600),
                                                                      darkEnd: .now.addingTimeInterval(5 * 3600), moonIllumination: 0.02)) {
    MeteorLiveActivity()
} contentStates: {
    MeteorActivityAttributes.ContentState()
}
#endif
