import XCTest

/// End-to-end tap path for the timer screen: open it from Home's Breastfeed button, start on
/// the left, switch, minimise to the pill, reopen, end, and close the summary.
final class BreastfeedingTimerFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartSwitchMinimiseEnd() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let breastfeed = app.buttons["breastfeedButton"].firstMatch
        XCTAssertTrue(breastfeed.waitForExistence(timeout: 10))
        breastfeed.tap()

        // The timer opens ready to start; start on the left.
        let startLeft = app.buttons["sideButton.left"].firstMatch
        XCTAssertTrue(startLeft.waitForExistence(timeout: 5))
        startLeft.tap()

        // Switch to the right.
        let right = app.buttons["sideButton.right"].firstMatch
        XCTAssertTrue(right.waitForExistence(timeout: 5))
        right.tap()
        XCTAssertTrue(app.buttons["End feed"].exists)

        // Minimise: the session keeps running and the pill appears.
        app.buttons["Minimise"].tap()
        let pill = app.buttons["activeSessionPill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5))

        // Reopen from the pill and end.
        pill.tap()
        let end = app.buttons["End feed"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Undo"].exists)
        done.tap()

        XCTAssertTrue(app.buttons["breastfeedButton"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activeSessionPill"].exists)
    }
}
