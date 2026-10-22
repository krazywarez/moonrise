import AppIntents
import SwiftUI
import WidgetKit

/// Control Center buttons that open a tab.
@MainActor
private func openTab(_ kind: String, _ tab: MoonriseTab, _ title: LocalizedStringResource, _ symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: kind) {
        ControlWidgetButton(action: OpenTabIntent(tab: tab)) {
            Label(title, systemImage: symbol)
        }
    }
    .displayName(title)
}

struct SkyControl: ControlWidget {
    var body: some ControlWidgetConfiguration { openTab("control.sky", .sky, "Tonight's sky", "sparkles") }
}

struct SunControl: ControlWidget {
    var body: some ControlWidgetConfiguration { openTab("control.sun", .sun, "Sun", "sun.max") }
}

struct LaunchesControl: ControlWidget {
    var body: some ControlWidgetConfiguration { openTab("control.launches", .launches, "Launches", "airplane.departure") }
}
