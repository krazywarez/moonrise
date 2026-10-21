import ActivityKit
import SwiftUI
import WidgetKit

struct LaunchLiveActivity: Widget {
    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LaunchActivityAttributes.self) { context in
            LaunchActivityView(context: context, ink: ink, accent: accent)
                .foregroundStyle(ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.rocket).font(.system(size: 14, weight: .medium))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state.net).font(.system(size: 14, weight: .medium).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.mission).font(.system(size: 12)).lineLimit(1).opacity(0.8)
                }
            } compactLeading: {
                IslandWidth {
                    Text("T−").font(.system(size: 12, weight: .medium))
                } limited: {
                    Image(systemName: "arrow.up").foregroundStyle(context.state.status == "Hold" ? accent : ink)
                }
            } compactTrailing: {
                IslandWidth {
                    liveTimer(context.state.net).font(.system(size: 12).monospacedDigit())
                } limited: {
                    if context.state.status == "Hold" {
                        Text("HOLD").font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                    } else {
                        liveTimer(context.state.net).font(.system(size: 12).monospacedDigit())
                    }
                }
            } minimal: {
                Image(systemName: "arrow.up")
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct LaunchActivityView: View {
    @Environment(\.activityFamily) private var family
    @Environment(\.isActivityFullscreen) private var fullscreen
    var context: ActivityViewContext<LaunchActivityAttributes>
    var ink: Color
    var accent: Color

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
            Text(context.attributes.rocket).font(.system(size: 13, weight: .medium)).lineLimit(1)
            HStack(spacing: 2) {
                Text(context.state.net > .now ? "T−" : "T+")
                liveTimer(context.state.net)
            }
            .font(.system(size: 17, weight: .medium).monospacedDigit())
            .foregroundStyle(context.state.status == "Hold" ? accent : ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.rocket).font(.system(size: 17, weight: .medium))
                Text(context.attributes.mission).font(.system(size: 13)).lineLimit(1).opacity(0.8)
                Text(context.attributes.location).font(.system(size: 11)).lineLimit(1).opacity(0.6)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(context.state.status.uppercased()).font(.system(size: 11, weight: .medium)).tracking(0.6)
                    .foregroundStyle(context.state.status == "Hold" ? accent : ink)
                HStack(spacing: 2) {
                    Text(context.state.net > .now ? "T−" : "T+")
                    countdown(context.state.net)
                }
                .font(.system(size: 22, weight: .medium).monospacedDigit())
            }
        }
        .padding(16)
    }
}

/// Counts down to T-0, then shows elapsed time.
private func countdown(_ net: Date) -> Text {
    net > .now ? Text(timerInterval: Date.now...net, countsDown: true) : Text(net, style: .timer)
}

#if DEBUG
private extension LaunchActivityAttributes {
    static var preview: Self {
        LaunchActivityAttributes(launchID: "preview", rocket: "Falcon 9 Block 5", mission: "Starlink Group 10-12",
                                 location: "SLC-40, Cape Canaveral SFS, Florida")
    }
}

private extension LaunchActivityAttributes.ContentState {
    static var go: Self { .init(net: .now.addingTimeInterval(12 * 60), status: "Go") }
    static var hold: Self { .init(net: .now.addingTimeInterval(12 * 60), status: "Hold") }
}

#Preview("Lock Screen", as: .content, using: LaunchActivityAttributes.preview) {
    LaunchLiveActivity()
} contentStates: {
    LaunchActivityAttributes.ContentState.go
    LaunchActivityAttributes.ContentState.hold
}

#Preview("Compact", as: .dynamicIsland(.compact), using: LaunchActivityAttributes.preview) {
    LaunchLiveActivity()
} contentStates: {
    LaunchActivityAttributes.ContentState.go
    LaunchActivityAttributes.ContentState.hold
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: LaunchActivityAttributes.preview) {
    LaunchLiveActivity()
} contentStates: {
    LaunchActivityAttributes.ContentState.go
    LaunchActivityAttributes.ContentState.hold
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: LaunchActivityAttributes.preview) {
    LaunchLiveActivity()
} contentStates: {
    LaunchActivityAttributes.ContentState.go
    LaunchActivityAttributes.ContentState.hold
}
#endif
