import ActivityKit
import Foundation
import Observation

/// Rockets and providers whose launches start a countdown on the Lock Screen an hour before liftoff, without opening
/// the app. Sends the server ActivityKit's push-to-start token and these lists, nothing else.
@MainActor
@Observable
final class LaunchStarts {
    static let shared = LaunchStarts()

    private static let rocketsKey = "followedRockets"
    private static let providersKey = "followedProviders"
    private static let tokenKey = "launchStartToken"

    private(set) var rockets = UserDefaults.standard.stringArray(forKey: LaunchStarts.rocketsKey) ?? []
    private(set) var providers = UserDefaults.standard.stringArray(forKey: LaunchStarts.providersKey) ?? []
    private(set) var status: String?
    private var started = false

    #if DEBUG
    private let environment = "sandbox"
    #else
    private let environment = "production"
    #endif

    private var token: String? { UserDefaults.standard.string(forKey: Self.tokenKey) }

    /// At launch: watches for the push-to-start token and ends duplicate countdowns (one followed by hand and one
    /// started by the server for the same launch).
    func start() {
        guard !started else { return }
        started = true
        Task {
            for await data in Activity<LaunchActivityAttributes>.pushToStartTokenUpdates {
                let hex = data.map { String(format: "%02x", $0) }.joined()
                guard hex != token else { continue }
                UserDefaults.standard.set(hex, forKey: Self.tokenKey)
                await sync()
            }
        }
        Task {
            for await new in Activity<LaunchActivityAttributes>.activityUpdates {
                await endIfDuplicate(id: new.id, launchID: new.attributes.launchID)
            }
        }
    }

    private func endIfDuplicate(id: String, launchID: String) async {
        guard Activity<LaunchActivityAttributes>.activities.contains(where: { $0.attributes.launchID == launchID && $0.id != id }) else { return }
        for a in Activity<LaunchActivityAttributes>.activities where a.id == id {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    func follows(rocket: String) -> Bool { rockets.contains(rocket) }
    func follows(provider: String) -> Bool { providers.contains(provider) }

    func set(rocket: String, _ on: Bool) async {
        rockets = toggled(rockets, rocket, on)
        UserDefaults.standard.set(rockets, forKey: Self.rocketsKey)
        await sync()
    }

    func set(provider: String, _ on: Bool) async {
        providers = toggled(providers, provider, on)
        UserDefaults.standard.set(providers, forKey: Self.providersKey)
        await sync()
    }

    private func toggled(_ list: [String], _ item: String, _ on: Bool) -> [String] {
        on ? (list.contains(item) ? list : list + [item]) : list.filter { $0 != item }
    }

    /// Registers the lists with the token; empty lists remove it from the server.
    func sync() async {
        guard let apiBase else { return }
        guard let token else {
            if !(rockets.isEmpty && providers.isEmpty) { status = "Countdowns start once iOS hands Moonrise a token; open the app again shortly." }
            return
        }
        let body: [String: Any] = ["token": token, "environment": environment, "rockets": rockets, "providers": providers]
        var req = URLRequest(url: apiBase.appending(path: "v1/launch-starts"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let (data, headers) = await AppAttest.sign(body, base: apiBase) {
            req.httpBody = data
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        } else {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let ok = ((try? await URLSession.shared.data(for: req))?.1 as? HTTPURLResponse)?.statusCode == 200
        status = ok ? nil : "Couldn't reach the Moonrise server. Your choices will be sent next time."
    }
}
