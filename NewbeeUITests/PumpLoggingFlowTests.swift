import XCTest

/// Pumping path: Home → Pumping → adjust a side → Save, then undo.
final class PumpLoggingFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLogPumpingThenUndo() throws {
        waitUntilANewSessionStartsToday()
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

    /// A new session ends now and lasts 15 minutes (`PumpLog.defaultDuration`), so just after
    /// midnight it starts yesterday and Home's "Today" total rightly stays empty. In that window
    /// (or just before midnight, when the day could turn mid-test) wait until the session will
    /// start today. The simulator shares the test runner's clock and time zone.
    private func waitUntilANewSessionStartsToday() {
        let calendar = Calendar.current
        let now = Date()
        let lastMidnight = calendar.startOfDay(for: now)
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: lastMidnight) else { return }
        let safeAfterMidnight: TimeInterval = 17 * 60
        let wakeUp: Date
        if now < lastMidnight.addingTimeInterval(safeAfterMidnight) {
            wakeUp = lastMidnight.addingTimeInterval(safeAfterMidnight)
        } else if now > nextMidnight.addingTimeInterval(-2 * 60) {
            wakeUp = nextMidnight.addingTimeInterval(safeAfterMidnight)
        } else {
            return
        }
        Thread.sleep(until: wakeUp)
    }

    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5) == .completed
    }
}
