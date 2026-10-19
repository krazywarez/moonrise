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
    @State private var router = Router.shared

    var body: some Scene {
        WindowGroup {
            TabView(selection: $router.tab) {
                Tab("Sky", systemImage: "sparkles", value: "sky") { SkyScreen() }
                Tab("System", systemImage: "circle.circle", value: "system") { SystemScreen() }
                Tab("Sun", systemImage: "sun.max", value: "sun") { SunScreen() }
                Tab("News & launches", systemImage: "airplane.departure", value: "launches") { LaunchesScreen() }
                Tab("Library", systemImage: "books.vertical", value: "library") { LibraryScreen() }
            }
            .tabViewStyle(.sidebarAdaptable)
            // Red tab highlight while the Sky tab is in night mode.
            .tint(router.tab == "sky" && nightActive ? SkyStyle.nightRed : nil)
            .preferredColorScheme(.dark)
            .environment(\.openURL, InAppBrowser.action)
            .fullScreenCover(isPresented: .constant(!onboarded)) {
                OnboardingScreen().preferredColorScheme(.dark)
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ImageLoader.configureURLCache()
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        log.info("APNs device token: \(token, privacy: .public)")
        Task { @MainActor in AuroraAlerts.shared.receivedToken(token) }
    }

    /// A news digest opens News & launches on the News switch.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.userInfo["tab"] as? String == "news" else { return }
        await MainActor.run {
            Router.shared.tab = "launches"
            Router.shared.showNews = true
        }
    }

    /// Show alerts as banners while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}
