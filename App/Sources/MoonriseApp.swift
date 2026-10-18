import SkyRenderer
import SwiftUI
import UIKit
import UserNotifications
import os

let log = Logger(subsystem: "sh.krz.moonrise", category: "app")

@main
struct MoonriseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.nightActive) private var nightActive = false
    @State private var tab = "sky"

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                Tab("Sky", systemImage: "sparkles", value: "sky") { SkyScreen() }
                Tab("System", systemImage: "circle.circle", value: "system") { SystemScreen() }
                Tab("Sun", systemImage: "sun.max", value: "sun") { SunScreen() }
                Tab("Launches", systemImage: "airplane.departure", value: "launches") { LaunchesScreen() }
                Tab("Library", systemImage: "books.vertical", value: "library") { LibraryScreen() }
            }
            // Red tab highlight while the Sky tab is in night mode.
            .tint(tab == "sky" && nightActive ? SkyStyle.nightRed : nil)
            .preferredColorScheme(.dark)
            .fullScreenCover(isPresented: .constant(!onboarded)) {
                OnboardingScreen().preferredColorScheme(.dark)
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        log.info("APNs device token: \(token, privacy: .public)")
        Task { @MainActor in AuroraAlerts.shared.receivedToken(token) }
    }

    /// Show alerts as banners while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}
