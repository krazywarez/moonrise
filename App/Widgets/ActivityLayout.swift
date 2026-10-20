import SwiftUI
import WidgetKit

/// `full` in a normal Dynamic Island, `limited` where it is narrow: landscape, iPhone Duo, or several
/// activities at once (iOS 27).
struct IslandWidth<Full: View, Limited: View>: View {
    @ViewBuilder var full: Full
    @ViewBuilder var limited: Limited

    var body: some View {
        if #available(iOS 27, *) {
            LimitedWidthReader(full: full, limited: limited)
        } else {
            full
        }
    }
}

@available(iOS 27, *)
private struct LimitedWidthReader<Full: View, Limited: View>: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimited
    var full: Full
    var limited: Limited

    var body: some View {
        if isLimited { limited } else { full }
    }
}

/// Counts down to `date`, or up from it once passed. Unlike `Text(timerInterval:)` it takes the width of its
/// digits, not the widest the timer could get.
func liveTimer(_ date: Date) -> Text {
    date > .now
        ? Text(.currentDate, format: .timer(countingDownIn: Date.now..<date))
        : Text(.currentDate, format: .stopwatch(startingAt: date, maxPrecision: .seconds(1)))
}
