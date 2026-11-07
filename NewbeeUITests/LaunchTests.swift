import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsAllFiveTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        for title in ["Home", "Calendar", "History", "Insights", "Tools"] {
            XCTAssertTrue(tabBar.buttons[title].exists, "Missing tab \(title)")
        }
        tabBar.buttons["Insights"].tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
    }
}
