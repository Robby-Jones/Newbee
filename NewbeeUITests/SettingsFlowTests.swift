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
        app.openYourData()
        let export = app.buttons["settings.exportPDF"]
        for _ in 0..<6 where !(export.exists && export.isHittable) { app.swipeUp() }
        export.tap()

        XCTAssertTrue(app.navigationBars["Feeding report"].waitForExistence(timeout: 5))
        // It used to close itself right after opening on the first tap.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(app.navigationBars["Feeding report"].exists, "The sheet closed itself")
        XCTAssertTrue(app.buttons["Custom"].exists)
        XCTAssertTrue(app.buttons["exportReport.create"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Your data"].waitForExistence(timeout: 5))
    }

    /// Settings → Import from Huckleberry opens the how-to with Choose File, and stays open.
    @MainActor
    func testHuckleberryImportSheetOpensFromSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let tab = app.tabBars.firstMatch.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        app.openYourData()
        let importButton = app.buttons["settings.importHuckleberry"]
        for _ in 0..<6 where !(importButton.exists && importButton.isHittable) { app.swipeUp() }
        importButton.tap()

        XCTAssertTrue(app.navigationBars["Import from Huckleberry"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(app.navigationBars["Import from Huckleberry"].exists, "The sheet closed itself")
        XCTAssertTrue(app.buttons["import.chooseFile"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Your data"].waitForExistence(timeout: 5))
        // Nothing imported yet, so there's nothing to remove.
        XCTAssertFalse(app.buttons["settings.removeImported"].exists)
    }

    /// Settings → About is its own page with the version and links.
    @MainActor
    func testAboutOpensAsItsOwnPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let tab = app.tabBars.firstMatch.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let about = app.buttons["settings.about"].firstMatch
        for _ in 0..<8 where !(about.exists && about.isHittable) { app.swipeUp() }
        about.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Version"].exists)
    }

    /// Delete all data opens its confirmation on the first tap and stays open.
    @MainActor
    func testDeleteAllSheetStaysOpenOnFirstTap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let tab = app.tabBars.firstMatch.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        app.openYourData()
        let delete = app.buttons["settings.deleteAll"]
        for _ in 0..<6 where !(delete.exists && delete.isHittable) { app.swipeUp() }
        delete.tap()

        let field = app.textFields["deleteAll.confirmField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(field.exists, "The sheet closed itself")
    }
}
