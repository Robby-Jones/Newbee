import XCTest

final class OnboardingFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Welcome (Huckleberry import there only) → Baby (name) → Stay in the loop → Home shows the
    /// name. One launch for the whole flow, since each launch costs about 10 s on CI.
    @MainActor
    func testOnboardingFlowSavesNameAndLandsOnHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-showOnboarding"]
        app.launch()

        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your data stays on this iPhone"].exists)

        // Welcome offers the Huckleberry import and returns to onboarding.
        let importLink = app.buttons["onboarding.importHuckleberry"]
        XCTAssertTrue(importLink.exists)
        importLink.tap()
        XCTAssertTrue(app.navigationBars["Import from Huckleberry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["import.chooseFile"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()

        let name = app.textFields["onboarding.babyName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        // The import is only on the welcome step.
        XCTAssertFalse(app.buttons["onboarding.importHuckleberry"].exists)
        name.tap()
        name.typeText("Ava")
        next.tap()

        XCTAssertTrue(app.switches["onboarding.reminders"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.skip"].exists, "The last step has no Skip")
        next.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ava"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSkipGoesStraightToHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-showOnboarding"]
        app.launch()

        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.next"].exists)
    }
}
