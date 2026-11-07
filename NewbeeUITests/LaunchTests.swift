import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsAllFourTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        for title in ["Home", "History", "Insights", "Settings"] {
            XCTAssertTrue(tabBar.buttons[title].exists, "Missing tab \(title)")
        }
        // Calendar and Tools were folded into History, Home and Insights.
        XCTAssertFalse(tabBar.buttons["Calendar"].exists)
        XCTAssertFalse(tabBar.buttons["Tools"].exists)
        tabBar.buttons["Insights"].tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
    }
}
