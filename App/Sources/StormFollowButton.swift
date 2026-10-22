import ActivityKit
import Feeds
import SwiftUI

/// Follows a geomagnetic storm on the Lock Screen. Updates arrive on the storm's broadcast channel, so the
/// server never learns who follows; the activity ends when the storm does, or after iOS's 8-hour limit.
struct StormFollowButton: View {
    var storm: StormCoverage
    var ink: Color
    @State private var following = false
    @State private var message: String?

    #if DEBUG
    private let environment = "sandbox"
    #else
    private let environment = "production"
    #endif

    var body: some View {
        if let channel = storm.channels[environment] {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    following ? unfollow() : follow(channel)
                } label: {
                    Label(following ? "Stop following" : "Follow storm on Lock Screen", systemImage: following ? "bell.slash" : "bell")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ink.opacity(0.5), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                if let message { Text(message).font(.footnote).dimmed(0.75) }
            }
            .padding(.top, 12)
            .onAppear { following = Activity<StormActivityAttributes>.activities.contains { $0.activityState == .active } }
        }
    }

    private func follow(_ channel: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off for Moonrise in Settings."
            return
        }
        let s = storm.state
        let state = StormActivityAttributes.ContentState(kp: s.kp, expectedKp: s.expectedKp, early: s.early, bz: s.bz, speed: s.speed, updated: .now)
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(45 * 60))
        do {
            _ = try Activity.request(attributes: StormActivityAttributes(startedAt: storm.startedAt), content: content, pushType: .channel(channel))
            following = true
            message = "Kp and the solar wind will update on the Lock Screen until the storm ends."
        } catch {
            message = "Couldn't follow the storm: \(error.localizedDescription)"
        }
    }

    private func unfollow() {
        Task {
            for a in Activity<StormActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            following = false
            message = nil
        }
    }
}
