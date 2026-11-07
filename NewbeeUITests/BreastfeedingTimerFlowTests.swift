import XCTest

/// End-to-end tap path for the timer screen: start from Home, switch, minimise to the pill,
/// reopen, end, and close the summary.
final class BreastfeedingTimerFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartSwitchMinimiseEnd() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let startLeft = app.buttons["sideButton.left"].firstMatch
        XCTAssertTrue(startLeft.waitForExistence(timeout: 10))
        startLeft.tap()

        // The timer opens; switch to the right.
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

        XCTAssertTrue(app.buttons["sideButton.left"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activeSessionPill"].exists)
    }
}
