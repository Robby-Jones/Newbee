import XCTest

/// Screenshots of new screens, taken to review them before a pull request: Actions → Screenshots →
/// Run workflow → "ReviewScreenshots". Not App Store material.
final class ReviewScreenshots: ScreenshotTestCase {
    /// Settings → Sharing in each state, and what "Delete all data" says while sharing.
    @MainActor
    func testSharing() throws {
        for state in ["notShared", "invited", "shared", "joined"] {
            let app = launch(["-sharingPreview", state])
            app.tabBars.buttons["Settings"].tap()
            let row = app.buttons["settings.sharing"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            reveal(row, in: app)
            settle()
            capture("sharing-\(state)")

            if state == "shared" || state == "joined" {
                let deleteAll = app.buttons["settings.deleteAll"].firstMatch
                reveal(deleteAll, in: app)
                deleteAll.tap()
                XCTAssertTrue(app.textFields["deleteAll.confirmField"].waitForExistence(timeout: 5))
                settle()
                capture("sharing-\(state)-delete-all")
            }
            app.terminate()
        }
    }

    /// The Night Shift card on Home in each state, and its section in Settings.
    @MainActor
    func testNightShift() throws {
        let controls = [
            "offerStart": "nightShift.start", "onDuty": "nightShift.end",
            "partnerOnDuty": "nightShift.takeOver", "summary": "nightShift.dismiss",
        ]
        for state in ["offerStart", "onDuty", "partnerOnDuty", "summary"] {
            let app = launch(["-sharingPreview", "shared", "-nightShiftPreview", state])
            let control = app.buttons[controls[state]!].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 15))
            reveal(control, in: app)
            settle()
            capture("night-shift-\(state)")

            if state == "onDuty" {
                app.tabBars.buttons["Settings"].tap()
                XCTAssertTrue(app.buttons["settings.sharing"].firstMatch.waitForExistence(timeout: 10))
                // Bring the whole Night Shift section, footer included, above the tab bar.
                let shiftEnd = app.descendants(matching: .any)["settings.nightShiftEnd"].firstMatch
                reveal(shiftEnd, in: app)
                app.swipeUp()
                settle()
                capture("night-shift-settings")
            }
            app.terminate()
        }
    }

    /// The bee from the app icon in each place it appears.
    @MainActor
    func testBeeMascot() throws {
        // Onboarding's welcome step, once the bee has flown in.
        var app = launch(["-showOnboarding"], sampleData: false)
        XCTAssertTrue(app.buttons["onboarding.next"].firstMatch.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.5)
        settle()
        capture("bee-onboarding")
        app.terminate()

        // An empty log: Home, History, Calendar and Insights.
        app = launch(sampleData: false)
        XCTAssertTrue(app.buttons["breastfeedButton"].firstMatch.waitForExistence(timeout: 15))
        settle()
        capture("bee-home-empty")
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        settle()
        capture("bee-history-empty")
        let calendarMode = app.segmentedControls.buttons["Calendar"].firstMatch
        if calendarMode.waitForExistence(timeout: 5) {
            calendarMode.tap()
            settle()
            capture("bee-calendar-empty")
        }
        app.tabBars.buttons["Insights"].tap()
        settle()
        capture("bee-insights-empty")
        app.terminate()

        // Home with feeds, the running timer, and Feed saved.
        app = launch(["-screenshotActiveFeed"])
        let endFeed = app.buttons["End feed"]
        if !endFeed.waitForExistence(timeout: 5) {
            let pill = app.buttons["activeSessionPill"].firstMatch
            XCTAssertTrue(pill.waitForExistence(timeout: 10))
            settle()
            capture("bee-home")
            pill.tap()
        }
        XCTAssertTrue(endFeed.waitForExistence(timeout: 5))
        settle()
        capture("bee-timer")
        endFeed.tap()
        XCTAssertTrue(app.buttons["summary.undo"].firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        settle()
        capture("bee-feed-saved")
        app.terminate()

        // Night Shift while the partner is on duty: the bee naps.
        app = launch(["-sharingPreview", "shared", "-nightShiftPreview", "partnerOnDuty"])
        let takeOver = app.buttons["nightShift.takeOver"].firstMatch
        XCTAssertTrue(takeOver.waitForExistence(timeout: 15))
        reveal(takeOver, in: app)
        settle()
        capture("bee-night-shift")
        app.terminate()
    }

    /// Scrolls the list until `element` can be tapped.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
