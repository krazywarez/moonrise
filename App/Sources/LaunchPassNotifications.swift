import Feeds
import SkyEngine
import SwiftUI
import UserNotifications

/// Opt-in local notifications 15 minutes before a launch's first visible pass. Passes are worked out on the
/// device and replaced whenever the launch list is loaded.
@MainActor
enum LaunchPassNotifications {
    static let followedKey = "launchPassFollowed"
    static let lead: TimeInterval = 15 * 60

    static var followed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: followedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: followedKey) }
    }

    private static func id(_ launch: Launch) -> String { "launch-pass-\(launch.id)" }

    nonisolated static func passes(of launch: Launch, observer: Observer) async -> [SatellitePass] {
        let elements = launch.elements ?? []
        return await Task.detached { SkyEngine.visiblePasses(of: elements, from: .now, observer: observer) }.value
    }

    static func follow(_ launch: Launch) async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        followed.insert(launch.id)
        await schedule(launch, observer: libraryObserver())
        return true
    }

    static func unfollow(_ launch: Launch) {
        followed.remove(launch.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(launch)])
    }

    /// Replaces the notifications for followed launches in `launches`; followed launches no longer listed are dropped.
    static func reschedule(_ launches: [Launch]) async {
        let listed = Set(launches.map(\.id))
        let center = UNUserNotificationCenter.current()
        let stale = followed.subtracting(listed)
        center.removePendingNotificationRequests(withIdentifiers: stale.map { "launch-pass-\($0)" })
        followed.formIntersection(listed)
        let observer = libraryObserver()
        for launch in launches where followed.contains(launch.id) {
            await schedule(launch, observer: observer)
        }
    }

    /// Loads the launch list, when anything is followed, and reschedules.
    static func refresh() async {
        guard !followed.isEmpty, let apiBase else { return }
        var list: LaunchList? = FeedMemo.get("launches", maxAge: 300)
        if list == nil { list = try? await LaunchFeed.fetch(base: apiBase) }
        guard let list else { return }
        await reschedule(list.launches + (list.recent ?? []))
    }

    private static func schedule(_ launch: Launch, observer: Observer) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id(launch)])
        guard let pass = await passes(of: launch, observer: observer).first(where: { $0.rise.addingTimeInterval(-lead) > .now }) else { return }
        let time = pass.rise.formatted(date: .omitted, time: .shortened)
        let content = UNMutableNotificationContent()
        content.title = "\(launch.mission ?? launch.rocket): first visible pass at \(time)"
        content.body = "\(pass.displayName) rises in the \(compass(pass.riseAzimuth)), highest \(Int(pass.maxAltitude.rounded()))°, sets in the \(compass(pass.setAzimuth)). Sunlit while your sky is dark."
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: pass.rise.addingTimeInterval(-lead))
        try? await center.add(UNNotificationRequest(identifier: id(launch), content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    static func compass(_ azimuth: Double) -> String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int(((azimuth + 22.5) / 45).rounded(.down)) % 8]
    }
}
