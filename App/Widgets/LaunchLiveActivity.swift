import ActivityKit
import SwiftUI
import WidgetKit

struct LaunchLiveActivity: Widget {
    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LaunchActivityAttributes.self) { context in
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.rocket).font(.system(size: 17, weight: .medium))
                    Text(context.attributes.mission).font(.system(size: 13)).lineLimit(1).opacity(0.8)
                    Text(context.attributes.location).font(.system(size: 11)).lineLimit(1).opacity(0.6)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.state.status.uppercased()).font(.system(size: 10, weight: .medium)).tracking(0.6)
                        .foregroundStyle(context.state.status == "Hold" ? accent : ink)
                    HStack(spacing: 2) {
                        Text(context.state.net > .now ? "T−" : "T+")
                        countdown(context.state.net)
                    }
                    .font(.system(size: 22, weight: .medium).monospacedDigit())
                }
            }
            .padding(16)
            .foregroundStyle(ink)
            .activityBackgroundTint(Color(red: 0.043, green: 0.078, blue: 0.141))
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
                Text("T−").font(.system(size: 12, weight: .medium))
            } compactTrailing: {
                countdown(context.state.net).font(.system(size: 12).monospacedDigit()).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "arrow.up")
            }
        }
    }

    /// Counts down to T-0, then shows elapsed time.
    private func countdown(_ net: Date) -> Text {
        net > .now ? Text(timerInterval: Date.now...net, countsDown: true) : Text(net, style: .timer)
    }
}
