import XCTest

/// Captures the App Store screenshots with two weeks of sample feeds (`ScreenshotSampleData`).
///
/// Skipped in normal test runs. The Screenshots workflow (`.github/workflows/screenshots.yml`)
/// runs it on a 6.3" iPhone Pro simulator (1206 x 2622) with `TEST_RUNNER_NEWBEE_SCREENSHOTS=1` and
/// `TEST_RUNNER_NEWBEE_SCREENSHOT_DIR=<folder>`; the PNGs land in that folder and are also kept
/// as test attachments.
final class AppStoreScreenshots: ScreenshotTestCase {
    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        // Home, History, Calendar and Insights, between feeds. Then the timer, then Home with the
        // On-Call Shift card.
        let app = launch()
        XCTAssertTrue(app.buttons["breastfeedButton"].firstMatch.waitForExistence(timeout: 15))
        settle()
        capture("01-home")

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["List"].firstMatch.waitForExistence(timeout: 5))
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
        let timerApp = launch(["-screenshotActiveFeed"])
        let pill = timerApp.buttons["activeSessionPill"].firstMatch
        let endFeed = timerApp.buttons["End feed"]
        if !endFeed.waitForExistence(timeout: 5) {
            XCTAssertTrue(pill.waitForExistence(timeout: 10), "No active feed: \(timerApp.debugDescription)")
            pill.tap()
        }
        XCTAssertTrue(endFeed.waitForExistence(timeout: 5))
        settle()
        capture("02-timer")
        timerApp.terminate()

        // Home with the On-Call Shift card below Today: shared with a partner, you're on call tonight.
        let onCallApp = launch(["-sharingPreview", "shared", "-nightShiftPreview", "onDuty"])
        let endShift = onCallApp.buttons["nightShift.end"].firstMatch
        XCTAssertTrue(endShift.waitForExistence(timeout: 15))
        settle()
        capture("07-on-call")

        // The same, scrolled a little so the whole card clears the tab bar. A slow drag with a
        // hold at the end stops the list where the finger lifts.
        let today = onCallApp.staticTexts["Today"].firstMatch
        XCTAssertTrue(today.exists)
        let from = today.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -90)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(endShift.isHittable)
        settle()
        capture("07-on-call-scrolled")
    }
}
