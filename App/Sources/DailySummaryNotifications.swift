import SkyEngine
import SwiftUI
import UserNotifications

/// Local notifications for the daily summary. The next seven are worked out on the device and
/// replaced each time the app becomes active or the location or setting changes.
enum DailySummaryNotifications {
    static let ids = (0..<7).map { "daily-summary-\($0)" }
    static let defaultMinutes = 18 * 60

    @MainActor
    static func reschedule(_ model: SkyModel) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.dailySummary) else { return }
        await model.refreshPasses()
        let observer = model.observer, passes = model.passes
        let minutes = defaults.object(forKey: SettingsKey.dailySummaryMinutes) as? Int ?? defaultMinutes
        let planned = await Task.detached { plan(observer: observer, passes: passes, minutes: minutes) }.value
        let calendar = Calendar.current
        for (id, fire, summary) in planned {
            let content = UNMutableNotificationContent()
            content.title = summary.title
            content.body = summary.body
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    nonisolated static func plan(observer: Observer, passes: [SatellitePass], minutes: Int, now: Date = .now) -> [(String, Date, DailySummary)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let events = SkyEngine.events(from: today, days: 8, observer: observer)
        return ids.enumerated().compactMap { i, id in
            guard let day = calendar.date(byAdding: .day, value: i, to: today),
                  let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > now,
                  let summary = try? DailySummary.make(at: fire, observer: observer, passes: passes, events: events)
            else { return nil }
            return (id, fire, summary)
        }
    }
}
