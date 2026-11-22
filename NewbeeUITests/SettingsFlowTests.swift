import XCTest

extension XCUIApplication {
    /// Settings → Your data, which is its own page.
    @MainActor
    func openYourData() {
        let row = buttons["settings.yourData"].firstMatch
        for _ in 0..<8 where !(row.exists && row.isHittable) { swipeUp() }
        row.tap()
        _ = navigationBars["Your data"].waitForExistence(timeout: 5)
    }
}

/// Settings checks share one app launch: each launch costs about 10 s on CI, so one walk through
/// the pages replaces five separate tests.
final class SettingsFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsPagesAndSheets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // Settings is its own tab; there's no second route to it from Home.
        let tab = app.tabBars.firstMatch.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["home.settings"].exists, "Home shouldn't duplicate the Settings tab")
        tab.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let reminders = app.switches["settings.reminderToggle"]
        for _ in 0..<3 where !reminders.exists { app.swipeUp() }
        XCTAssertTrue(reminders.exists)

        // About is its own page.
        let about = app.buttons["settings.about"].firstMatch
        for _ in 0..<8 where !(about.exists && about.isHittable) { app.swipeUp() }
        about.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Version"].exists)
        app.navigationBars["About"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.openYourData()
        XCTAssertTrue(app.navigationBars["Your data"].exists)

        // Export feeding report opens the range sheet.
        let export = app.buttons["settings.exportPDF"]
        for _ in 0..<6 where !(export.exists && export.isHittable) { app.swipeUp() }
        export.tap()
        XCTAssertTrue(app.navigationBars["Feeding report"].waitForExistence(timeout: 5))
        // It used to close itself right after opening on the first tap.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(app.navigationBars["Feeding report"].exists, "The report sheet closed itself")
        XCTAssertTrue(app.buttons["Custom"].exists)
        XCTAssertTrue(app.buttons["exportReport.create"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Your data"].waitForExistence(timeout: 5))

        // Import from Huckleberry opens the how-to and stays open.
        let importButton = app.buttons["settings.importHuckleberry"]
        for _ in 0..<6 where !(importButton.exists && importButton.isHittable) { app.swipeUp() }
        importButton.tap()
        XCTAssertTrue(app.navigationBars["Import from Huckleberry"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(app.navigationBars["Import from Huckleberry"].exists, "The import sheet closed itself")
        XCTAssertTrue(app.buttons["import.chooseFile"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Your data"].waitForExistence(timeout: 5))
        // Nothing imported yet, so there's nothing to remove.
        XCTAssertFalse(app.buttons["settings.removeImported"].exists)

        // Last, because it leaves the confirmation open.
        // Delete all data opens its confirmation on the first tap.
        let delete = app.buttons["settings.deleteAll"]
        for _ in 0..<6 where !(delete.exists && delete.isHittable) { app.swipeUp() }
        delete.tap()
        let field = app.textFields["deleteAll.confirmField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(field.exists, "The delete-all sheet closed itself")
    }
}
