import Foundation
import Observation
import SkyEngine
import UIKit
import UserNotifications

/// Registers this device with the backend for aurora pushes. Sends only the push
/// token, a 5° geomagnetic latitude band and the UTC offset.
@MainActor
@Observable
final class AuroraAlerts {
    static let shared = AuroraAlerts()

    private static let enabledKey = "auroraAlerts"
    private static let tokenKey = "apnsToken"

    private(set) var enabled = UserDefaults.standard.bool(forKey: AuroraAlerts.enabledKey)
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
        if on {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                status = "Notifications are off for Moonrise. Turn them on in the Settings app."
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
        }
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        await sync()
    }

    /// Registers or unregisters to match `enabled`.
    func sync() async {
        guard let apiBase, let token else { return }
        if enabled {
            guard let observer else { return }
            let body: [String: Any] = [
                "token": token,
                "environment": environment,
                "band": Geomagnetic.band(observer),
                "utcOffsetMinutes": TimeZone.current.secondsFromGMT() / 60,
                "aurora": true,
            ]
            var req = URLRequest(url: apiBase.appending(path: "v1/devices"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
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
