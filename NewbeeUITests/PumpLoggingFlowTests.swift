import XCTest

/// Pumping path: Home → Pumping → adjust a side → Save, then undo.
final class PumpLoggingFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLogPumpingThenUndo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLocale", "en_GB"]
        app.launch()

        let logPump = app.buttons["logPumpButton"].firstMatch
        XCTAssertTrue(logPump.waitForExistence(timeout: 10))
        XCTAssertTrue(logPump.label.contains("None today"), logPump.label)
        logPump.tap()

        // Opens pre-filled with 60 mL a side; one more step on the left makes 65 + 60.
        let more = app.buttons["pump.more.left"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        app.buttons["pump.save"].firstMatch.tap()

        XCTAssertTrue(waitForLabel(of: logPump, containing: "Today: 1 session · 125 mL"), logPump.label)
        let undo = app.buttons["pump.undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()

        XCTAssertTrue(waitForLabel(of: logPump, containing: "None today"), logPump.label)
    }

    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5) == .completed
    }
}
