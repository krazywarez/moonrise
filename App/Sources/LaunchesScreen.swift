import ActivityKit
import Feeds
import Library
import SkyEngine
import SwiftUI

/// Backend base URL from Info.plist (MOONRISE_API_URL build setting); nil when unset.
let apiBase: URL? = (Bundle.main.object(forInfoDictionaryKey: "MoonriseAPIURL") as? String)
    .flatMap { $0.isEmpty ? nil : URL(string: $0) }

/// Tab and News/Launches switch that a notification tap can change, and what Siri or Spotlight asked to show.
@MainActor
@Observable
final class Router {
    static let shared = Router()
    var tab = "sky"
    var showNews = false
    /// Presented as a sheet over any tab.
    var libraryPage: LibraryPage?
    /// Typed into the Library's search field.
    var libraryQuery: String?
    /// Turned to by the Sky tab once its scene exists.
    var skyTarget: Tour.Target?
}

struct LaunchesScreen: View {
    @State private var router = Router.shared
    @State private var list: LaunchList?
    @State private var error: String?
    @State private var selected: Launch?
    @State private var newsReload = 0

    private let ink = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.19)
    private let background = Color.black

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("News & launches").font(.title.weight(.medium))
                Rectangle().fill(accent).frame(width: 48, height: 5).padding(.top, 8).padding(.bottom, 12)
                Picker("Show", selection: $router.showNews) {
                    Text("Launches").tag(false)
                    Text("News").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)

                if router.showNews {
                    NewsList(ink: ink, accent: accent, reload: newsReload)
                } else {
                    launches
                }
            }
            .padding(.horizontal, 20)
            .readableWidth()
        }
        .foregroundStyle(ink)
        .background(background.ignoresSafeArea())
        .refreshable { if router.showNews { newsReload += 1 } else { await load(force: true) } }
        .task { await load() }
        .sheet(item: $selected) { LaunchDetail(launch: $0, ink: ink, accent: accent, background: background) }
    }

    @ViewBuilder
    private var launches: some View {
                if let error {
                    Text(error).font(.footnote).foregroundStyle(accent).padding(.vertical, 12)
                }
                if let list {
                    ForEach(Array(list.launches.enumerated()), id: \.element.id) { i, launch in
                        Button { selected = launch } label: { row(launch, index: i + 1) }
                            .buttonStyle(.plain)
                    }
                    if let recent = list.recent, !recent.isEmpty {
                        Text("Recent").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6).padding(.top, 20).padding(.bottom, 4)
                        ForEach(Array(recent.enumerated()), id: \.element.id) { i, launch in
                            Button { selected = launch } label: { row(launch, index: i + 1) }
                                .buttonStyle(.plain)
                        }
                    }
                    Text("Launch data: The Space Devs, Launch Library 2.")
                        .font(.caption2).dimmed(0.5).padding(.vertical, 16)
                } else if error == nil {
                    ProgressView().tint(ink).padding(.top, 40).frame(maxWidth: .infinity)
                }
    }

    /// The backend polls every 10 minutes; a visit within 5 minutes of the last load reuses it.
    private func load(force: Bool = false) async {
        guard let apiBase else { error = "No backend configured for this build."; return }
        if !force, let cached: LaunchList = FeedMemo.get("launches", maxAge: 300) { list = cached; return }
        do {
            list = try await LaunchFeed.fetch(base: apiBase)
            if let list {
                FeedMemo.set("launches", list)
                await LaunchPassNotifications.reschedule(list.launches + (list.recent ?? []))
            }
            error = nil
        } catch {
            self.error = "Couldn't load launches. Pull to retry."
        }
    }

    private func row(_ l: Launch, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%02d", index)).font(.caption2.monospacedDigit()).dimmed(0.5)
                Text(l.net.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.caption2).dimmed(0.7)
                Spacer()
                StatusTag(status: l.status, ink: ink, accent: accent)
            }
            Text(l.rocket).font(.title2.weight(.medium))
            if let m = l.mission { Text(m).font(.subheadline) }
            HStack {
                Text("\(l.provider) · \(l.location)").font(.caption2).dimmed(0.7)
                Spacer()
                Countdown(to: l.net).font(.footnote.weight(.medium).monospacedDigit())
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.25)).frame(height: 0.5) }
        .contentShape(Rectangle())
    }
}

struct StatusTag: View {
    var status: String
    var ink: Color
    var accent: Color

    var body: some View {
        Text(status.uppercased())
            .font(.caption2.weight(.medium))
            .tracking(0.6)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(status == "Go" ? Color.black : ink)
            .background(status == "Go" ? ink : (status == "Hold" ? accent : ink.opacity(0.15)), in: .rect(cornerRadius: 2))
    }
}

/// T− countdown, ticking each second; T+ once the time has passed.
struct Countdown: View {
    var to: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Self.format(to.timeIntervalSince(ctx.date)))
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(abs(seconds))
        let sign = seconds >= 0 ? "T−" : "T+"
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60, sec = s % 60
        return d > 0 ? String(format: "%@%dd %02d:%02d:%02d", sign, d, h, m, sec) : String(format: "%@%02d:%02d:%02d", sign, h, m, sec)
    }
}

struct LaunchDetail: View {
    var launch: Launch
    var ink: Color
    var accent: Color
    var background: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatusTag(status: launch.status, ink: ink, accent: accent)
                    Text(launch.statusName).font(.caption).dimmed(0.7)
                }
                Text(launch.rocket).font(.title.weight(.medium))
                if let m = launch.mission { Text(m).font(.body) }
                Countdown(to: launch.net).font(.largeTitle.weight(.medium).monospacedDigit()).padding(.vertical, 6)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    fact("Provider", launch.provider)
                    fact("Launch time", launch.net.formatted(date: .abbreviated, time: .shortened))
                    if let a = launch.windowStart, let b = launch.windowEnd, a != b {
                        fact("Window", "\(a.formatted(date: .omitted, time: .shortened))–\(b.formatted(date: .omitted, time: .shortened))")
                    }
                    if let t = launch.missionType { fact("Mission", t) }
                    if let o = launch.orbit { fact("Orbit", o) }
                    fact("Pad", launch.pad)
                    fact("Location", launch.location)
                }
                .font(.subheadline)
                visibility.padding(.top, 8)
                followButton.padding(.top, 8)
                if let message { Text(message).font(.caption).dimmed(0.7) }
                if let d = launch.missionDescription {
                    Text(d).font(.subheadline).dimmed(0.85).padding(.top, 8)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(ink)
        .presentationBackground(background)
        .presentationDetents([.medium, .large])
    }

    @State private var message: String?
    @State private var following = false
    @State private var passes: [SatellitePass]?
    @State private var notifying = false
    @State private var notifyMessage: String?

    /// First visible passes over the observer, worked out on the device.
    @ViewBuilder
    private var visibility: some View {
        if let elements = launch.elements, !elements.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Visibility").font(.caption2.weight(.medium)).textCase(.uppercase).tracking(0.8).dimmed(0.6)
                if let passes {
                    if let first = passes.first {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            fact("First visible pass", describe(first))
                            ForEach(passes.filter { $0.name == first.name }.dropFirst().prefix(2)) { fact("Later", describe($0)) }
                        }
                        .font(.subheadline)
                        Text("\(first.displayName). Sunlit while your sky is dark; it may still be too faint to see\(elements.contains { $0.OBJECT_NAME.hasPrefix("Starlink train") } ? ", though new trains are often visible" : "").")
                            .font(.caption).dimmed(0.7)
                        Text(source).font(.caption2).dimmed(0.5)
                        notifyButton
                        if let notifyMessage { Text(notifyMessage).font(.caption).dimmed(0.7) }
                    } else {
                        Text("No visible pass from here in the next three days.").font(.subheadline).dimmed(0.7)
                    }
                } else {
                    ProgressView().tint(ink)
                }
            }
            .task {
                notifying = LaunchPassNotifications.followed.contains(launch.id)
                passes = await LaunchPassNotifications.passes(of: launch, observer: libraryObserver())
            }
        } else if launch.net < .now {
            Text("No orbit published for this launch yet.").font(.caption).dimmed(0.7)
        }
    }

    private var source: String {
        let credit = launch.elementsSource == "supgp" ? "SpaceX via CelesTrak" : "CelesTrak"
        return launch.elementsSource == "supgp" && launch.net > .now ? "Predicted before launch · \(credit)" : "Orbit: \(credit)"
    }

    private func describe(_ p: SatellitePass) -> String {
        p.rise.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            + " · \(LaunchPassNotifications.compass(p.riseAzimuth)) → \(LaunchPassNotifications.compass(p.setAzimuth)), highest \(Int(p.maxAltitude.rounded()))°"
    }

    private var notifyButton: some View {
        Button {
            if notifying {
                LaunchPassNotifications.unfollow(launch)
                notifying = false
                notifyMessage = nil
            } else {
                Task {
                    notifying = await LaunchPassNotifications.follow(launch)
                    notifyMessage = notifying ? nil : "Notifications are off for Moonrise. Turn them on in the Settings app."
                }
            }
        } label: {
            Label(notifying ? "Don't notify me" : "Notify me 15 minutes before", systemImage: notifying ? "bell.slash" : "bell")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ink.opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var followButton: some View {
        Button {
            following ? unfollow() : follow()
        } label: {
            Label(following ? "Stop following" : "Follow on Lock Screen", systemImage: following ? "bell.slash" : "bell")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ink.opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onAppear {
            following = Activity<LaunchActivityAttributes>.activities.contains { $0.attributes.launchID == launch.id }
        }
    }

    private func follow() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off for Moonrise in Settings."
            return
        }
        let attributes = LaunchActivityAttributes(launchID: launch.id, rocket: launch.rocket, mission: launch.mission ?? launch.name, location: launch.location)
        let state = LaunchActivityAttributes.ContentState(net: launch.net, status: launch.status)
        let content = ActivityContent(state: state, staleDate: launch.net.addingTimeInterval(3600))
        // Live Activities end after 8 hours, so one for a later launch starts an hour before it.
        let start = launch.net.addingTimeInterval(-3600)
        do {
            if start > .now {
                let alert = AlertConfiguration(title: "\(attributes.rocket) launches in an hour", body: "\(attributes.mission)", sound: .default)
                _ = try Activity.request(attributes: attributes, content: content, style: .standard, alertConfiguration: alert, start: start)
                message = "Countdown will appear on the Lock Screen an hour before launch."
            } else {
                _ = try Activity.request(attributes: attributes, content: content)
                message = "Countdown added to the Lock Screen."
            }
            following = true
        } catch {
            message = "Couldn't start the countdown: \(error.localizedDescription)"
        }
    }

    private func unfollow() {
        let id = launch.id
        Task {
            for a in Activity<LaunchActivityAttributes>.activities where a.attributes.launchID == id {
                await a.end(nil, dismissalPolicy: .immediate)
            }
            following = false
            message = nil
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).dimmed(0.6)
            Text(value)
        }
    }
}
