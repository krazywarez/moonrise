#if DEBUG
import ActivityKit
import SwiftUI

/// Starts Live Activities a few minutes out, to check the Lock Screen and Dynamic Island without waiting
/// for a real pass, launch or eclipse. Debug builds only.
struct SampleActivitiesSection: View {
    @State private var message: String?

    var body: some View {
        Section {
            Button("Pass rising in 2 minutes") { startPass() }
            Button("Launch at T−5 minutes") { startLaunch() }
            Button("Eclipse, first contact in 3 minutes") { startEclipse() }
            Button("G2 storm") { startStorm() }
            Button("End all sample activities", role: .destructive) { Task { await endAll() } }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Sample Live Activities")
        } footer: {
            Text("Debug builds only. Samples are named Test.")
        }
    }

    private func startPass() {
        let rise = Date.now.addingTimeInterval(120)
        let attributes = PassActivityAttributes(name: "Test", rise: rise, peak: rise.addingTimeInterval(180),
                                                set: rise.addingTimeInterval(360), riseAzimuth: 236, setAzimuth: 52,
                                                maxAltitude: 64, visible: true)
        request(attributes, ActivityContent(state: .init(), staleDate: attributes.set.addingTimeInterval(60)))
    }

    private func startLaunch() {
        let attributes = LaunchActivityAttributes(launchID: "sample", rocket: "Test rocket", mission: "Test launch",
                                                  location: "Sample pad")
        let net = Date.now.addingTimeInterval(300)
        request(attributes, ActivityContent(state: .init(net: net, status: "Go"), staleDate: net.addingTimeInterval(3600)))
    }

    private func startEclipse() {
        let c1 = Date.now.addingTimeInterval(180)
        let attributes = EclipseActivityAttributes(
            kind: "Total", site: "Test site", c1: c1, c2: c1.addingTimeInterval(240), peak: c1.addingTimeInterval(330),
            c3: c1.addingTimeInterval(420), c4: c1.addingTimeInterval(900), timeZone: TimeZone.current.identifier
        )
        request(attributes, ActivityContent(state: .init(), staleDate: attributes.c4))
    }

    private func startStorm() {
        let state = StormActivityAttributes.ContentState(kp: 6.33, expectedKp: 7, early: false, bz: -14, speed: 640, updated: .now)
        request(StormActivityAttributes(startedAt: .now), ActivityContent(state: state, staleDate: .now.addingTimeInterval(45 * 60)))
    }

    private func request<A: ActivityAttributes>(_ attributes: A, _ content: ActivityContent<A.ContentState>) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off for Moonrise in Settings."
            return
        }
        do {
            _ = try Activity.request(attributes: attributes, content: content)
            message = nil
        } catch {
            message = "Couldn't start it: \(error.localizedDescription)"
        }
    }

    private func endAll() async {
        for a in Activity<PassActivityAttributes>.activities where a.attributes.name == "Test" {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        for a in Activity<LaunchActivityAttributes>.activities where a.attributes.launchID == "sample" {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        for a in Activity<EclipseActivityAttributes>.activities where a.attributes.site == "Test site" {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        message = nil
    }
}
#endif
