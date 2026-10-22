import ActivityKit
import SkyEngine
import SwiftUI

/// Bell on a meteor shower row: puts the peak night on the Lock Screen from 10 minutes before dark. Hidden more
/// than a day ahead.
struct MeteorFollowButton: View {
    var event: SkyEvent
    @State private var following = false
    @State private var message: String?

    private var shower: String { event.title.replacingOccurrences(of: " peak", with: "") }

    var body: some View {
        if event.activityStart(now: .now) != nil {
            Button {
                following ? unfollow() : follow()
            } label: {
                Image(systemName: following ? "bell.fill" : "bell")
                    .font(.subheadline)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(following ? "Stop following on Lock Screen" : "Follow on Lock Screen")
            .onAppear { following = Activity<MeteorActivityAttributes>.activities.contains { $0.attributes.shower == shower } }
            .alert(message ?? "", isPresented: Binding { message != nil } set: { if !$0 { message = nil } }) {}
        }
    }

    private func follow() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off for Moonrise in Settings."
            return
        }
        guard let start = event.activityStart(now: .now), let window = event.window else { return }
        let attributes = MeteorActivityAttributes(shower: shower, zhr: event.zhr ?? 0, darkStart: window.start, darkEnd: window.end,
                                                  moonIllumination: event.moonIllumination ?? 0)
        let content = ActivityContent(state: MeteorActivityAttributes.ContentState(), staleDate: window.end)
        do {
            if start > .now {
                let alert = AlertConfiguration(
                    title: "\(event.title) tonight",
                    body: "Dark from \(window.start.formatted(date: .omitted, time: .shortened)). Up to \(attributes.zhr) meteors an hour under dark skies.",
                    sound: .default)
                _ = try Activity.request(attributes: attributes, content: content, style: .standard, alertConfiguration: alert, start: start)
            } else {
                _ = try Activity.request(attributes: attributes, content: content)
            }
            following = true
        } catch {
            message = "Couldn't add the shower: \(error.localizedDescription)"
        }
    }

    private func unfollow() {
        let shower = shower
        Task {
            for a in Activity<MeteorActivityAttributes>.activities where a.attributes.shower == shower {
                await a.end(nil, dismissalPolicy: .immediate)
            }
            following = false
        }
    }
}
