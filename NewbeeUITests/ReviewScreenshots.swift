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

    /// The since-last-feed Live Activity (always dark), drawn in the app on mock Lock Screen and
    /// Dynamic Island shapes (`LiveActivityReviewGallery`).
    @MainActor
    func testSinceLastFeedLiveActivity() throws {
        for page in ["lockScreen", "island"] {
            let app = launch(["-liveActivityReview", page])
            let plus = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Open Newbee to start a feed")).firstMatch
            XCTAssertTrue(plus.waitForExistence(timeout: 15))
            settle()
            capture("since-last-feed-\(page)")
            app.terminate()
        }
    }

    /// Settings with help text behind (i) buttons in the section headers, and two of the popovers.
    @MainActor
    func testSettingsInfoButtons() throws {
        let app = launch(["-sharingPreview", "shared"])
        app.tabBars.buttons["Settings"].tap()
        let sharingInfo = app.buttons["settings.info.sharing"].firstMatch
        XCTAssertTrue(sharingInfo.waitForExistence(timeout: 10))
        settle()
        capture("settings-info-top")

        sharingInfo.tap()
        XCTAssertTrue(app.staticTexts["settings.infoText"].firstMatch.waitForExistence(timeout: 5))
        settle()
        capture("settings-info-sharing-popover")
        // A tap outside the popover (on the title) closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        settle()

        let remindersInfo = app.buttons["settings.info.reminders"].firstMatch
        reveal(remindersInfo, in: app)
        settle()
        capture("settings-info-middle")
        remindersInfo.tap()
        XCTAssertTrue(app.staticTexts["settings.infoText"].firstMatch.waitForExistence(timeout: 5))
        settle()
        capture("settings-info-reminders-popover")
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
