import XCTest

final class SettingsFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Settings is its own tab; there's no second route to it from Home.
    @MainActor
    func testSettingsOpensFromItsTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let tab = app.tabBars.firstMatch.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["home.settings"].exists, "Home shouldn't duplicate the Settings tab")
        tab.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let reminders = app.switches["settings.reminderToggle"]
        for _ in 0..<3 where !reminders.exists { app.swipeUp() }
        XCTAssertTrue(reminders.exists)
    }

    /// Settings → Export feeding report opens the range sheet with the presets and Create PDF.
    @MainActor
    func testFeedingReportSheetOpensFromSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let tab = app.tabBars.firstMatch.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let export = app.buttons["settings.exportPDF"]
        for _ in 0..<6 where !(export.exists && export.isHittable) { app.swipeUp() }
        export.tap()

        XCTAssertTrue(app.navigationBars["Feeding report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Custom"].exists)
        XCTAssertTrue(app.buttons["exportReport.create"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}
