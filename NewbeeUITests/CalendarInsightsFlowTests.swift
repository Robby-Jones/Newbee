import XCTest

/// Calendar and Insights pick up a feed logged on Home (docs/UX_SPEC.md §3.5, §3.8).
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

        // Calendar opens on today, selected, with the bottle in its summary.
        app.tabBars.buttons["Calendar"].tap()
        let openDay = app.buttons["calendar.openDay"].firstMatch
        XCTAssertTrue(openDay.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, containing: "120 mL").exists)
        openDay.tap()
        // Feed rows combine their texts into one element.
        XCTAssertTrue(element(in: app, containing: "Bottle · 120 mL").waitForExistence(timeout: 5))

        // Insights shows the bottle card and the one-day note.
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["Bottles"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Feeds per day"].firstMatch.exists)
    }

    private func element(in app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
