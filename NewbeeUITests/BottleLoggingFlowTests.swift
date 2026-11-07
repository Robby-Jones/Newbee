import XCTest

/// Two-tap bottle path (docs/UX_SPEC.md §3.4): Log bottle → preset → Save, then undo.
final class BottleLoggingFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLogPresetBottleThenUndo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLocale", "en_GB"]
        app.launch()

        let logBottle = app.buttons["logBottleButton"].firstMatch
        XCTAssertTrue(logBottle.waitForExistence(timeout: 10))
        XCTAssertTrue(logBottle.label.contains("None today"), logBottle.label)
        logBottle.tap()

        let preset = app.buttons["bottle.preset.120"].firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        app.buttons["bottle.save"].firstMatch.tap()

        XCTAssertTrue(waitForLabel(of: logBottle, containing: "Today: 1 bottle · 120 mL"), logBottle.label)
        let undo = app.buttons["bottle.undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()

        XCTAssertTrue(waitForLabel(of: logBottle, containing: "None today"), logBottle.label)
    }

    /// The card combines its texts into the button's label.
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5) == .completed
    }
}
