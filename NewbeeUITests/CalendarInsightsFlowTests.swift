import XCTest

/// History (list and calendar) and Insights pick up a feed logged on Home (docs/UX_SPEC.md §3.5, §3.6, §3.8).
final class CalendarInsightsFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLoggedBottleShowsInCalendarAndInsights() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLocale", "en_GB"]
        app.launch()

        let logBottle = app.buttons["logBottleButton"].firstMatch
        XCTAssertTrue(logBottle.waitForExistence(timeout: 10))
        logBottle.tap()
        let preset = app.buttons["bottle.preset.120"].firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        app.buttons["bottle.save"].firstMatch.tap()
        // Wait for the sheet to close and the save to land before leaving Home.
        let saved = NSPredicate(format: "label CONTAINS %@", "120 mL")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: saved, object: logBottle)], timeout: 5), .completed, logBottle.label)

        // History's Calendar mode opens on today, selected, with the bottle in its summary.
        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 5), "History tab missing")
        historyTab.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5), "History didn't open")
        XCTAssertTrue(element(in: app, containing: "Bottle · 120 mL").waitForExistence(timeout: 5), "List has no bottle row")
        let calendarMode = app.segmentedControls.buttons["Calendar"].firstMatch
        XCTAssertTrue(calendarMode.waitForExistence(timeout: 5), "Calendar mode missing")
        calendarMode.tap()
        let openDay = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "calendar.openDay", "Open day")).firstMatch
        if !openDay.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(openDay.waitForExistence(timeout: 5), "Open day missing:\n\(app.debugDescription)")
        XCTAssertTrue(element(in: app, containing: "120 mL").exists, "Day summary has no 120 mL")
        openDay.tap()
        // Feed rows combine their texts into one element.
        XCTAssertTrue(element(in: app, containing: "Bottle · 120 mL").waitForExistence(timeout: 5), "Day list has no bottle row")

        // Insights shows the bottle card and the one-day note.
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["Feeds per day"].firstMatch.waitForExistence(timeout: 5), "No feeds card")
        XCTAssertTrue(app.staticTexts["Bottles"].firstMatch.exists, "No bottles card")
    }

    @MainActor
    private func element(in app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
