import XCTest

/// Runs Xcode's accessibility audit on each main screen and prints every issue.
/// Issues are recorded, not failed, so one run reports everything.
final class AccessibilityAuditTests: XCTestCase {
    var app: XCUIApplication!
    var issues: [String] = []

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-onboarded", "YES", "-locationMode", "city", "-nightMode", "off"]
        app.launch()
    }

    private func audit(_ screen: String, _ types: XCUIAccessibilityAuditType = .all) {
        try? app.performAccessibilityAudit(for: types) { issue in
            let label = issue.element?.label ?? ""
            let id = issue.element?.identifier ?? ""
            let line = "[\(screen)] \(issue.auditType): \(issue.compactDescription) — element: '\(label)' \(id)"
            self.issues.append(line)
            print("A11Y " + line)
            return true
        }
    }

    private func tab(_ name: String) {
        app.tabBars.buttons[name].firstMatch.tap()
        sleep(3)
    }

    func testAuditAllScreens() {
        sleep(3)
        audit("Sky")
        app.buttons["Explore"].tap()
        app.buttons["Settings"].tap(); sleep(1)
        audit("Settings")
        app.buttons["Done"].tap(); sleep(1)
        tab("System"); audit("System")
        tab("Sun"); audit("Sun")
        tab("News & launches"); audit("News & launches")
        tab("Library"); audit("Library")
        app.buttons["See all Planets"].firstMatch.tap(); sleep(1)
        app.staticTexts["Saturn"].firstMatch.tap(); sleep(2)
        audit("Library page: Saturn")
        print("ACCESSIBILITY-AUDIT-BEGIN")
        issues.forEach { print($0) }
        print("ACCESSIBILITY-AUDIT-END \(issues.count) issues")
    }
}
