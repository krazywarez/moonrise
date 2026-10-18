import ActivityKit
import SwiftUI
import WidgetKit

struct EventLiveActivity: Widget {
    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventActivityAttributes.self) { context in
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
            .foregroundStyle(ink)
            .activityBackgroundTint(Color(red: 0.043, green: 0.078, blue: 0.141))
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
                Text(context.attributes.launch, style: .timer).font(.system(size: 12).monospacedDigit()).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "moon.stars")
            }
        }
    }
}
