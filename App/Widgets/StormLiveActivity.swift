import ActivityKit
import SwiftUI
import WidgetKit

struct StormLiveActivity: Widget {
    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StormActivityAttributes.self) { context in
            StormActivityView(context: context)
                .foregroundStyle(ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Geomagnetic storm").font(.system(size: 14, weight: .medium)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(kp(context.state.kp)).font(.system(size: 14, weight: .medium).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.headline).font(.system(size: 12))
                        Text(wind(context.state)).font(.system(size: 12).monospacedDigit()).opacity(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "sun.max.trianglebadge.exclamationmark")
            } compactTrailing: {
                Text(StormActivityAttributes.ContentState.scale(context.state.kp) ?? kp(context.state.kp))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            } minimal: {
                Image(systemName: "sun.max.trianglebadge.exclamationmark")
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

private func kp(_ v: Double) -> String { "Kp \(v.formatted(.number.precision(.fractionLength(0...1))))" }

/// Latest Bz and speed at L1; empty when the solar wind feed is down.
private func wind(_ s: StormActivityAttributes.ContentState) -> String {
    [s.bz.map { "Bz \(Int($0.rounded())) nT" }, s.speed.map { "\(Int($0.rounded())) km/s" }].compactMap { $0 }.joined(separator: " · ")
}

private struct StormActivityView: View {
    @Environment(\.activityFamily) private var family
    @Environment(\.isActivityFullscreen) private var fullscreen
    var context: ActivityViewContext<StormActivityAttributes>

    private var state: StormActivityAttributes.ContentState { context.state }

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
            Text("Geomagnetic storm").font(.system(size: 13, weight: .medium)).lineLimit(1)
            Text(StormActivityAttributes.ContentState.scale(state.kp).map { "\($0) · \(kp(state.kp))" } ?? kp(state.kp))
                .font(.system(size: 17, weight: .medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Geomagnetic storm").font(.system(size: 11, weight: .medium)).textCase(.uppercase).tracking(0.6).opacity(0.8)
            Text(state.headline).font(.system(size: 17, weight: .medium))
            if state.expectedKp > state.kp, StormActivityAttributes.ContentState.scale(state.kp) != nil {
                Text("Up to \(kp(state.expectedKp)) in the next 3 hours").font(.system(size: 13))
            }
            HStack {
                Text(wind(state)).font(.system(size: 12).monospacedDigit()).opacity(0.8)
                Spacer()
                Group {
                    if context.isStale {
                        Text("No update since \(state.updated.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("Updated \(state.updated, style: .relative) ago")
                    }
                }
                .font(.system(size: 12)).opacity(0.8)
            }
        }
        .padding(16)
    }
}

#if DEBUG
private extension StormActivityAttributes.ContentState {
    static var g2: Self { .init(kp: 6.33, expectedKp: 7, early: false, bz: -14.2, speed: 640, updated: .now.addingTimeInterval(-300)) }
    static var early: Self { .init(kp: 3.67, expectedKp: 4, early: true, bz: -11, speed: 520, updated: .now) }
}

#Preview("Lock Screen", as: .content, using: StormActivityAttributes(startedAt: .now.addingTimeInterval(-7200))) {
    StormLiveActivity()
} contentStates: {
    StormActivityAttributes.ContentState.g2
    StormActivityAttributes.ContentState.early
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: StormActivityAttributes(startedAt: .now)) {
    StormLiveActivity()
} contentStates: {
    StormActivityAttributes.ContentState.g2
}
#endif
