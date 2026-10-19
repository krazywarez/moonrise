import SafariServices
import SwiftUI
import UIKit

/// Opens web links in Safari's in-app browser over the current screen, so people stay in the app.
/// Other schemes (mailto:, settings) go to the system as usual.
@MainActor
enum InAppBrowser {
    static let action = OpenURLAction { url in
        guard url.scheme == "https" || url.scheme == "http", let top = topViewController() else { return .systemAction }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = UIColor(red: 0.88, green: 0.24, blue: 0.19, alpha: 1)
        safari.dismissButtonStyle = .done
        top.present(safari, animated: true)
        return .handled
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
