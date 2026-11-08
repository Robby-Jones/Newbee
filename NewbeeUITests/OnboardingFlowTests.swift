import XCTest

final class OnboardingFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Welcome → Baby (name) → Stay in the loop → Home shows the name.
    @MainActor
    func testOnboardingSavesNameAndLandsOnHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-showOnboarding"]
        app.launch()

        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your data stays on this iPhone"].exists)
        next.tap()

        let name = app.textFields["onboarding.babyName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
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
