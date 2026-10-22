import Foundation
import Observation
import SkyEngine
import UIKit
import UserNotifications

/// Registers this device with the backend for aurora and news pushes. Sends only the push
/// token, a 5° geomagnetic latitude band, the UTC offset and which alerts are on.
@MainActor
@Observable
final class AuroraAlerts {
    static let shared = AuroraAlerts()

    private static let enabledKey = "auroraAlerts"
    private static let newsKey = "newsAlerts"
    private static let tokenKey = "apnsToken"

    private(set) var enabled = UserDefaults.standard.bool(forKey: AuroraAlerts.enabledKey)
    /// The daily news digest at 09:00.
    private(set) var news = UserDefaults.standard.bool(forKey: AuroraAlerts.newsKey)
    private(set) var status: String?
    private var observer: Observer?

    #if DEBUG
    private let environment = "sandbox"
    #else
    private let environment = "production"
    #endif

    private var token: String? { UserDefaults.standard.string(forKey: Self.tokenKey) }

    /// Called by the app delegate whenever iOS hands over a device token.
    func receivedToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        Task { await sync() }
    }

    /// Called when the sky's location changes, so the band stays current.
    func update(observer: Observer) {
        guard observer != self.observer else { return }
        self.observer = observer
        Task { await sync() }
    }

    func setEnabled(_ on: Bool) async {
        if on, !(await permitted()) { return }
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        await sync()
    }

    func setNews(_ on: Bool) async {
        if on, !(await permitted()) { return }
        news = on
        UserDefaults.standard.set(on, forKey: Self.newsKey)
        await sync()
    }

    private func permitted() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            status = "Notifications are off for Moonrise. Turn them on in the Settings app."
        }
        return granted
    }

    /// Registers or unregisters to match `enabled`.
    func sync() async {
        guard let apiBase, let token else { return }
        if enabled || news {
            guard let observer else { return }
            let body: [String: Any] = [
                "token": token,
                "environment": environment,
                "band": Geomagnetic.band(observer),
                "utcOffsetMinutes": TimeZone.current.secondsFromGMT() / 60,
                "aurora": enabled,
                "news": news,
            ]
            var req = URLRequest(url: apiBase.appending(path: "v1/devices"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            if let (data, headers) = await AppAttest.sign(body, base: apiBase) {
                req.httpBody = data
                for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            } else {
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }
            let ok = await send(req)
            status = ok ? nil : "Couldn't reach the Moonrise server. Alerts will register next time."
        } else {
            var req = URLRequest(url: apiBase.appending(path: "v1/devices/\(token)"))
            req.httpMethod = "DELETE"
            _ = await send(req)
            status = nil
        }
    }

    func sendTest() async {
        guard let apiBase, let token else { status = "No device token yet."; return }
        var req = URLRequest(url: apiBase.appending(path: "v1/devices/\(token)/test"))
        req.httpMethod = "POST"
        guard let (_, response) = try? await URLSession.shared.data(for: req), let http = response as? HTTPURLResponse else {
            status = "Couldn't reach the Moonrise server."
            return
        }
        status = switch http.statusCode {
        case 200: "Test alert sent."
        case 429: "A test was sent recently. Try again in a few minutes."
        case 404: "This device isn't registered yet."
        default: "The test alert failed (\(http.statusCode))."
        }
    }

    private func send(_ req: URLRequest) async -> Bool {
        guard let (_, response) = try? await URLSession.shared.data(for: req) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
