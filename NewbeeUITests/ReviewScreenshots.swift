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
                // Delete all is on the Your data page.
                app.openYourData()
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

            if state == "offerStart" {
                // Tapping Start asks for the end time.
                control.tap()
                let confirm = app.buttons["nightShift.confirmStart"].firstMatch
                XCTAssertTrue(confirm.waitForExistence(timeout: 10))
                settle()
                capture("night-shift-pick-end")
            }

            if state == "onDuty" {
                app.tabBars.buttons["Settings"].tap()
                XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
                // Bring the whole On-Call Shift section, footer included, above the tab bar.
                let alarm = app.descendants(matching: .any)["settings.nightShiftAlarm"].firstMatch
                reveal(alarm, in: app)
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
        for page in ["lockScreen", "lockScreenPink", "lockScreenThemes", "island"] {
            let app = launch(["-liveActivityReview", page])
            let plus = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Open Newbee to start a feed")).firstMatch
            XCTAssertTrue(plus.waitForExistence(timeout: 15))
            settle()
            capture("since-last-feed-\(page)")
            app.terminate()
        }
    }

    /// The pink theme: Settings → Appearance with the theme and icon pickers, then each tab in
    /// pink. The simulator's appearance (light or dark) comes from the workflow input.
    @MainActor
    func testPinkTheme() throws {
        let app = launch(["-uiTestColorTheme", "pink"])
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
        settle()
        capture("pink-home")
        app.tabBars.buttons["History"].tap()
        settle()
        capture("pink-history")
        app.tabBars.buttons["Insights"].tap()
        settle()
        capture("pink-insights")
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        // A Form row can expose its buttons as any element type.
        let swatch = app.descendants(matching: .any)["settings.theme.standard"].firstMatch
        for _ in 0..<15 where !(swatch.exists && swatch.isHittable) {
            app.swipeUp()
        }
        settle()
        capture("pink-settings-appearance")
        // Back to indigo from the picker, to check the switch redraws everything.
        guard swatch.isHittable else {
            XCTFail("The Indigo swatch isn't on screen")
            return
        }
        swatch.tap()
        settle()
        capture("pink-settings-switched-to-indigo")
        app.terminate()
    }

    /// Home and Insights in each of the other color themes.
    @MainActor
    func testOtherColorThemes() throws {
        for theme in ["sage", "ocean", "lavender", "peach"] {
            let app = launch(["-uiTestColorTheme", theme])
            XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
            settle()
            capture("theme-\(theme)-home")
            app.tabBars.buttons["Insights"].tap()
            settle()
            capture("theme-\(theme)-insights")
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

        let notificationsInfo = app.buttons["settings.info.notifications"].firstMatch
        reveal(notificationsInfo, in: app)
        settle()
        capture("settings-info-middle")
        notificationsInfo.tap()
        XCTAssertTrue(app.staticTexts["settings.infoText"].firstMatch.waitForExistence(timeout: 5))
        settle()
        capture("settings-info-notifications-popover")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        settle()

        // Your data and About open as their own pages.
        let bottomRows = app.buttons["settings.about"].firstMatch
        reveal(bottomRows, in: app)
        app.swipeUp()
        settle()
        capture("settings-info-bottom")
        app.openYourData()
        settle()
        capture("settings-your-data")
        app.navigationBars.buttons.firstMatch.tap()
        let about = app.buttons["settings.about"].firstMatch
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        settle()
        capture("settings-about")
        app.terminate()
    }

    /// Settings → Breastfeeding: "Suggested starting side" with its "Switch from" choice, the
    /// picker's options, and the section once a fixed side hides "Switch from".
    @MainActor
    func testStartingSideSetting() throws {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()
        let picker = app.descendants(matching: .any)["settings.startingSide"].firstMatch
        let switchFrom = app.descendants(matching: .any)["settings.switchFrom"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        reveal(switchFrom, in: app)
        settle()
        capture("starting-side-alternate")

        switchFrom.tap()
        XCTAssertTrue(app.buttons["Side you started on"].firstMatch.waitForExistence(timeout: 5))
        settle()
        capture("starting-side-switch-from-menu")
        app.buttons["Side you started on"].firstMatch.tap()
        settle()

        // Room above the header so the popover isn't cut off by the navigation bar.
        app.swipeDown()
        settle()
        app.buttons["settings.info.breastfeeding"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["settings.infoText"].firstMatch.waitForExistence(timeout: 5))
        settle()
        capture("starting-side-info")
        // A tap in the left margin, well below the popover, closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.75)).tap()
        settle()
        reveal(picker, in: app)

        picker.tap()
        XCTAssertTrue(app.buttons["Always right"].firstMatch.waitForExistence(timeout: 5))
        settle()
        capture("starting-side-menu")
        app.buttons["Always right"].firstMatch.tap()
        settle()
        capture("starting-side-always-right")

        // Home says "Next: Right" and the timer tags Right as Suggested.
        app.tabBars.buttons["Home"].tap()
        let breastfeed = app.buttons["breastfeedButton"].firstMatch
        XCTAssertTrue(breastfeed.waitForExistence(timeout: 10))
        settle()
        capture("starting-side-home")
        breastfeed.tap()
        XCTAssertTrue(app.buttons["sideButton.right"].firstMatch.waitForExistence(timeout: 10))
        settle()
        capture("starting-side-timer")
        app.terminate()
    }

    /// Settings → Bottle and pumping with "Log pumping as total only" on, the Log Pumping sheet
    /// asking for one total, and History with the new total next to older left/right sessions.
    @MainActor
    func testPumpingTotalOnly() throws {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["settings.pumpTotalOnly"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        reveal(toggle, in: app)
        settle()
        capture("pump-total-settings-off")
        // The switch itself sits at the trailing edge of the row.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        settle()
        let presets = app.descendants(matching: .any)["settings.pumpTotalPresets"].firstMatch
        XCTAssertTrue(presets.waitForExistence(timeout: 5))
        presets.tap()
        settle()
        capture("pump-total-settings-on")

        app.tabBars.buttons["Home"].tap()
        let logPump = app.buttons["logPumpButton"].firstMatch
        XCTAssertTrue(logPump.waitForExistence(timeout: 10))
        logPump.tap()
        XCTAssertTrue(app.buttons["pump.more.total"].firstMatch.waitForExistence(timeout: 5))
        settle()
        capture("pump-total-sheet")
        app.buttons["pump.save"].firstMatch.tap()
        settle()

        app.tabBars.buttons["History"].tap()
        settle()
        capture("pump-total-history")
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
