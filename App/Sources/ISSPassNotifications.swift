import SkyEngine
import SwiftUI
import UserNotifications

/// Opt-in local notifications 15 minutes before each visible ISS pass in the next three days. Worked out on the
/// device and replaced whenever the daily summary is.
enum ISSPassNotifications {
    static let ids = (0..<8).map { "iss-pass-\($0)" }
    static let lead: TimeInterval = 15 * 60

    @MainActor
    static func reschedule(_ model: SkyModel) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard UserDefaults.standard.bool(forKey: SettingsKey.issPasses) else { return }
        await model.refreshPasses()
        for (id, pass) in zip(ids, plan(model.passes)) {
            let content = UNMutableNotificationContent()
            content.title = "ISS pass in 15 minutes"
            content.body = body(pass)
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: pass.rise.timeIntervalSinceNow - lead, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    /// Visible ISS passes whose alert time is still ahead, soonest first.
    nonisolated static func plan(_ passes: [SatellitePass], now: Date = .now) -> [SatellitePass] {
        passes.filter { $0.displayName == "ISS" && $0.visible && $0.rise.addingTimeInterval(-lead) > now }
            .sorted { $0.rise < $1.rise }
    }

    nonisolated static func body(_ p: SatellitePass) -> String {
        let t = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        return "Rises \(t(p.rise)) in the \(SkyEngine.compass(p.riseAzimuth)), highest \(Int(p.maxAltitude.rounded()))° at \(t(p.peak)), sets \(t(p.set)) in the \(SkyEngine.compass(p.setAzimuth))."
    }
}
