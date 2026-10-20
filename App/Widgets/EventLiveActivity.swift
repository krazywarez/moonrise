import ActivityKit
import SwiftUI
import WidgetKit

struct EventLiveActivity: Widget {
    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventActivityAttributes.self) { context in
            EventActivityView(context: context)
                .foregroundStyle(ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.title).font(.system(size: 14, weight: .medium))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.launch, style: .timer).font(.system(size: 14).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.state.phase) · \(Int(context.state.distanceKm).formatted()) km").font(.system(size: 12)).opacity(0.8)
                }
            } compactLeading: {
                Image(systemName: "moon.stars")
            } compactTrailing: {
                IslandWidth {
                    liveTimer(context.attributes.launch).font(.system(size: 12).monospacedDigit())
                } limited: {
                    // Mission time in days once past the first day; the full timer does not fit.
                    if context.attributes.launch < .now.addingTimeInterval(-86_400) {
                        Text("\(Int(-context.attributes.launch.timeIntervalSinceNow / 86_400)) d").font(.system(size: 12).monospacedDigit())
                    } else {
                        liveTimer(context.attributes.launch).font(.system(size: 12).monospacedDigit())
                    }
                }
            } minimal: {
                Image(systemName: "moon.stars")
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct EventActivityView: View {
    @Environment(\.activityFamily) private var family
    @Environment(\.isActivityFullscreen) private var fullscreen
    var context: ActivityViewContext<EventActivityAttributes>

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
            Text(context.attributes.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            liveTimer(context.attributes.launch).font(.system(size: 17, weight: .medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(context.attributes.title).font(.system(size: 17, weight: .medium))
                Spacer()
                Text(context.attributes.launch, style: .timer).font(.system(size: 17, weight: .medium).monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            Text(context.state.phase).font(.system(size: 14))
            HStack {
                Text("\(Int(context.state.distanceKm).formatted()) km from Earth").font(.system(size: 12)).opacity(0.8)
                Spacer()
                if let next = context.state.next, let at = context.state.nextAt {
                    Text("\(next) \(at, style: .relative)").font(.system(size: 12)).opacity(0.8).lineLimit(1)
                }
            }
        }
        .padding(16)
    }
}
