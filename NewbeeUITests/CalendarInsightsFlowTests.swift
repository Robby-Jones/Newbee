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
        // Wait for the sheet to close and the save to land before leaving Home.
        let saved = NSPredicate(format: "label CONTAINS %@", "120 mL")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: saved, object: logBottle)], timeout: 5), .completed, logBottle.label)

        // Calendar opens on today, selected, with the bottle in its summary.
        let calendarTab = app.tabBars.buttons["Calendar"]
        XCTAssertTrue(calendarTab.waitForExistence(timeout: 5), "Calendar tab missing")
        // The undo toast sits just above the tab bar and can catch the tap on iOS 17: let it go.
        let undo = app.buttons["bottle.undo"].firstMatch
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: undo)
        _ = XCTWaiter().wait(for: [gone], timeout: 10)
        calendarTab.tap()
        if !app.navigationBars["Calendar"].waitForExistence(timeout: 3) {
            calendarTab.tap()
        }
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 5), "Calendar didn't open:\n\(app.debugDescription)")
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
