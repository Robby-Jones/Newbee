import XCTest

/// Captures the App Store screenshots with two weeks of sample feeds (`ScreenshotSampleData`).
///
/// Skipped in normal test runs. The Screenshots workflow (`.github/workflows/screenshots.yml`)
/// runs it on a 6.9" iPhone simulator with `TEST_RUNNER_NEWBEE_SCREENSHOTS=1` and
/// `TEST_RUNNER_NEWBEE_SCREENSHOT_DIR=<folder>`; the PNGs land in that folder and are also kept
/// as test attachments.
final class AppStoreScreenshots: XCTestCase {
    private var outputDirectory: URL?

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["NEWBEE_SCREENSHOTS"] == "1", "Screenshots run only from the Screenshots workflow")
        continueAfterFailure = false
        if let path = environment["NEWBEE_SCREENSHOT_DIR"], !path.isEmpty {
            outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory!, withIntermediateDirectories: true)
        }
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        // Home, History, Calendar and Insights, between feeds.
        let app = launch(activeFeed: false)
        XCTAssertTrue(app.buttons["breastfeedButton"].firstMatch.waitForExistence(timeout: 15))
        settle()
        capture("01-home")

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        settle()
        capture("03-history")

        let calendarMode = app.segmentedControls.buttons["Calendar"].firstMatch
        XCTAssertTrue(calendarMode.waitForExistence(timeout: 5))
        calendarMode.tap()
        // Month shows two weeks of feeds; Week can be nearly empty early in the week.
        let month = app.segmentedControls.buttons["Month"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        month.tap()
        settle()
        capture("04-calendar")

        app.tabBars.buttons["Insights"].tap()
        let feedsCard = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Feeds '")).firstMatch
        XCTAssertTrue(feedsCard.waitForExistence(timeout: 5))
        settle()
        capture("05-insights")

        app.tabBars.buttons["Home"].tap()
        let logBottle = app.buttons["logBottleButton"].firstMatch
        XCTAssertTrue(logBottle.waitForExistence(timeout: 5))
        logBottle.tap()
        XCTAssertTrue(app.buttons["bottle.save"].firstMatch.waitForExistence(timeout: 5))
        settle()
        capture("06-log-bottle")
        app.terminate()

        // The timer, 12 minutes into a feed on the left.
        let timerApp = launch(activeFeed: true)
        let pill = timerApp.buttons["activeSessionPill"].firstMatch
        let endFeed = timerApp.buttons["End feed"]
        if !endFeed.waitForExistence(timeout: 5) {
            XCTAssertTrue(pill.waitForExistence(timeout: 10), "No active feed: \(timerApp.debugDescription)")
            pill.tap()
        }
        XCTAssertTrue(endFeed.waitForExistence(timeout: 5))
        settle()
        capture("02-timer")
    }

    @MainActor
    private func launch(activeFeed: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-screenshotData",
            "-AppleLanguages", "(en-US)", "-AppleLocale", "en_US",
        ]
        if activeFeed { app.launchArguments.append("-screenshotActiveFeed") }
        // Chosen by the workflow so it is evening in the app, whatever time the run starts.
        if let timeZone = ProcessInfo.processInfo.environment["NEWBEE_SCREENSHOT_TZ"], !timeZone.isEmpty {
            app.launchEnvironment["TZ"] = timeZone
        }
        app.launch()
        return app
    }

    /// Lets animations and charts finish drawing.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    @MainActor
    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let outputDirectory {
            let url = outputDirectory.appendingPathComponent("\(name).png")
            XCTAssertNoThrow(try screenshot.pngRepresentation.write(to: url))
        }
    }
}
