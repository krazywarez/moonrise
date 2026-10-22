import XCTest

/// Captures the App Store and website screenshots from Denver, night mode off. Saved as PNGs to the folder in
/// SCREENSHOT_DIR (pass TEST_RUNNER_SCREENSHOT_DIR to xcodebuild); skipped without it.
final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!
    var folder: URL!

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { throw XCTSkip("SCREENSHOT_DIR not set") }
        folder = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments += ["-onboarded", "YES", "-locationMode", "city", "-cityName", "Denver",
                                "-cityLatitude", "39.7392", "-cityLongitude", "-104.9903", "-nightMode", "off"]
        app.launch()
    }

    private func shoot(_ name: String, wait: UInt32 = 3) throws {
        sleep(wait)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appending(path: "\(name).png"))
    }

    private func tab(_ name: String) {
        app.tabBars.buttons[name].firstMatch.tap()
    }

    func testScreenshots() throws {
        try shoot("01-sky", wait: 6)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Moon'")).firstMatch.tap()
        try shoot("02-tonight")
        app.swipeDown(velocity: .fast)
        sleep(1)
        tab("System")
        app.buttons["Map"].firstMatch.tap()
        try shoot("03-system", wait: 4)
        app.buttons["3D"].firstMatch.tap()
        try shoot("04-3d", wait: 5)
        tab("Sun")
        try shoot("05-sun", wait: 8)
        tab("News & launches")
        try shoot("06-launches", wait: 5)
        tab("Library")
        try shoot("07-library", wait: 3)
        app.buttons["See all Planets"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Jupiter"].firstMatch.tap()
        try shoot("08-jupiter", wait: 3)
    }
}
