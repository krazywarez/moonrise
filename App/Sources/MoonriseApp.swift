import SwiftUI
import UIKit
import os

let log = Logger(subsystem: "sh.krz.moonrise", category: "app")

@main
struct MoonriseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Sky", systemImage: "sparkles") { SkyScreen() }
                Tab("Sun", systemImage: "sun.max") { SunScreen() }
            }
            .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        log.info("APNs device token: \(token, privacy: .public)")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}
