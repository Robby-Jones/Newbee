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

    /// The Done button above the keyboard dismisses it while a note is being typed.
    @MainActor
    func testKeyboardDoneDismissesNoteKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let logBottle = app.buttons["logBottleButton"].firstMatch
        XCTAssertTrue(logBottle.waitForExistence(timeout: 10))
        logBottle.tap()

        let notes = app.textViews["bottle.notes"].exists
            ? app.textViews["bottle.notes"].firstMatch
            : app.textFields["bottle.notes"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        for _ in 0..<3 where !notes.isHittable { app.swipeUp() }
        notes.tap()
        notes.typeText("Sleepy")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

        let done = app.buttons["keyboard.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
    }

    /// The card combines its texts into the button's label.
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5) == .completed
    }
}
