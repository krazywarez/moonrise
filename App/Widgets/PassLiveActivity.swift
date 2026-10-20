import ActivityKit
import SkyEngine
import SwiftUI
import WidgetKit

struct PassLiveActivity: Widget {
    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PassActivityAttributes.self) { context in
            PassActivityView(context: context, ink: ink)
                .foregroundStyle(ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    liveTimer(context.attributes.rise).font(.system(size: 14, weight: .medium).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.isStale {
                        Text("Passed \(time(context.attributes.set))").font(.system(size: 12)).opacity(0.8)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary(context.attributes)).font(.system(size: 12).monospacedDigit()).lineLimit(1).opacity(0.8)
                            passProgress(context.attributes, ink: ink)
                        }
                    }
                }
            } compactLeading: {
                IslandWidth {
                    Text(context.attributes.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                } limited: {
                    Image(systemName: "sparkle")
                }
            } compactTrailing: {
                liveTimer(context.attributes.rise).font(.system(size: 12).monospacedDigit())
            } minimal: {
                Image(systemName: "sparkle")
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct PassActivityView: View {
    @Environment(\.activityFamily) private var family
    @Environment(\.isActivityFullscreen) private var fullscreen
    var context: ActivityViewContext<PassActivityAttributes>
    var ink: Color

    private var pass: PassActivityAttributes { context.attributes }

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
            Text("\(pass.name) \(Int(pass.maxAltitude.rounded()))°").font(.system(size: 13, weight: .medium)).lineLimit(1)
            if context.isStale {
                Text("Passed \(time(pass.set))").font(.system(size: 13).monospacedDigit()).opacity(0.8)
            } else {
                liveTimer(pass.rise).font(.system(size: 17, weight: .medium).monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(pass.name) pass").font(.system(size: 10, weight: .medium)).textCase(.uppercase).tracking(0.6).opacity(0.8)
                if pass.visible {
                    Text("Visible").font(.system(size: 10, weight: .medium)).textCase(.uppercase).tracking(0.6)
                }
                Spacer()
                if !context.isStale {
                    liveTimer(pass.rise).font(.system(size: 17, weight: .medium).monospacedDigit())
                }
            }
            Rectangle().fill(ink.opacity(0.4)).frame(height: 0.5)
            if context.isStale {
                Text("Passed \(time(pass.set))").font(.system(size: 17, weight: .medium).monospacedDigit())
            } else {
                HStack(alignment: .top) {
                    column("Rise", time(pass.rise), SkyEngine.compass(pass.riseAzimuth))
                    Spacer()
                    column("Highest", time(pass.peak), "\(Int(pass.maxAltitude.rounded()))°")
                    Spacer()
                    column("Set", time(pass.set), SkyEngine.compass(pass.setAzimuth))
                }
                passProgress(pass, ink: ink)
            }
        }
        .padding(16)
    }

    private func column(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10, weight: .medium)).textCase(.uppercase).tracking(0.6).opacity(0.6)
            Text("\(value) \(detail)").font(.system(size: 15, weight: .medium).monospacedDigit())
        }
    }
}

/// Empty before rise, full at set, with the time left in the pass beside it.
private func passProgress(_ pass: PassActivityAttributes, ink: Color) -> some View {
    HStack(spacing: 8) {
        ProgressView(timerInterval: pass.rise...pass.set, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            .tint(ink)
        Text(.currentDate, format: .timer(countingDownIn: pass.rise..<pass.set))
            .font(.system(size: 12).monospacedDigit()).opacity(0.8)
    }
}

private func summary(_ pass: PassActivityAttributes) -> String {
    "Rises \(SkyEngine.compass(pass.riseAzimuth)) \(time(pass.rise)), highest \(Int(pass.maxAltitude.rounded()))°, sets \(SkyEngine.compass(pass.setAzimuth))"
}

private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

#if DEBUG
private extension PassActivityAttributes {
    static var preview: Self {
        PassActivityAttributes(name: "ISS", rise: .now.addingTimeInterval(4 * 60), peak: .now.addingTimeInterval(7.5 * 60),
                               set: .now.addingTimeInterval(11 * 60), riseAzimuth: 236, setAzimuth: 52, maxAltitude: 64,
                               visible: true)
    }
}

#Preview("Lock Screen", as: .content, using: PassActivityAttributes.preview) {
    PassLiveActivity()
} contentStates: {
    PassActivityAttributes.ContentState()
}

#Preview("Compact", as: .dynamicIsland(.compact), using: PassActivityAttributes.preview) {
    PassLiveActivity()
} contentStates: {
    PassActivityAttributes.ContentState()
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: PassActivityAttributes.preview) {
    PassLiveActivity()
} contentStates: {
    PassActivityAttributes.ContentState()
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: PassActivityAttributes.preview) {
    PassLiveActivity()
} contentStates: {
    PassActivityAttributes.ContentState()
}
#endif
