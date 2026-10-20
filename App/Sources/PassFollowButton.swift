import ActivityKit
import SkyEngine
import SwiftUI

/// Bell on a pass row: puts the pass on the Lock Screen from 10 minutes before rise. Hidden for passes more
/// than a day away.
struct PassFollowButton: View {
    var pass: SatellitePass
    @State private var following = false
    @State private var message: String?

    var body: some View {
        if pass.activityStart(now: .now) != nil {
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
            .onAppear { following = Activity<PassActivityAttributes>.activities.contains { matches($0.attributes, pass) } }
            .alert(message ?? "", isPresented: Binding { message != nil } set: { if !$0 { message = nil } }) {}
        }
    }

    private func follow() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off for Moonrise in Settings."
            return
        }
        guard let start = pass.activityStart(now: .now) else { return }
        let attributes = PassActivityAttributes(name: pass.displayName, rise: pass.rise, peak: pass.peak, set: pass.set,
                                                riseAzimuth: pass.riseAzimuth, setAzimuth: pass.setAzimuth,
                                                maxAltitude: pass.maxAltitude, visible: pass.visible)
        // It cannot end itself without an update, so it goes stale a minute after set.
        let content = ActivityContent(state: PassActivityAttributes.ContentState(), staleDate: pass.set.addingTimeInterval(60))
        do {
            if start > .now {
                let rise = pass.rise.formatted(date: .omitted, time: .shortened)
                let alert = AlertConfiguration(
                    title: "\(pass.displayName) pass in 10 minutes",
                    body: "Rises \(SkyEngine.compass(pass.riseAzimuth)) at \(rise), highest \(Int(pass.maxAltitude.rounded()))°, sets \(SkyEngine.compass(pass.setAzimuth)).",
                    sound: .default)
                _ = try Activity.request(attributes: attributes, content: content, style: .standard, alertConfiguration: alert, start: start)
            } else {
                _ = try Activity.request(attributes: attributes, content: content)
            }
            following = true
        } catch {
            message = "Couldn't add the pass: \(error.localizedDescription)"
        }
    }

    private func unfollow() {
        let pass = pass
        Task {
            for a in Activity<PassActivityAttributes>.activities where matches(a.attributes, pass) {
                await a.end(nil, dismissalPolicy: .immediate)
            }
            following = false
        }
    }
}

/// Rise times shift by a 20 s step each time passes are recomputed.
private func matches(_ attributes: PassActivityAttributes, _ pass: SatellitePass) -> Bool {
    attributes.name == pass.displayName && abs(attributes.rise.timeIntervalSince(pass.rise)) < 120
}
