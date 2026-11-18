import XCTest

/// Shared by the tests that take screenshots with sample feeds (`ScreenshotSampleData`): the App
/// Store set and the review set for new screens.
///
/// Skipped in normal test runs. The Screenshots workflow (`.github/workflows/screenshots.yml`)
/// runs them on a 6.3" iPhone Pro simulator (1206 x 2622) with `TEST_RUNNER_NEWBEE_SCREENSHOTS=1` and
/// `TEST_RUNNER_NEWBEE_SCREENSHOT_DIR=<folder>`; the PNGs land in that folder and are also kept
/// as test attachments.
class ScreenshotTestCase: XCTestCase {
    private var outputDirectory: URL?

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["NEWBEE_SCREENSHOTS"] == "1", "Screenshots run only from the Screenshots workflow")
        continueAfterFailure = false
        if let path = environment["NEWBEE_SCREENSHOT_DIR"], !path.isEmpty {
            outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory!, withIntermediateDirectories: true)
        }
    }

    /// Launches the app with sample feeds (or an empty log), in US English, plus `arguments`.
    @MainActor
    func launch(_ arguments: [String] = [], sampleData: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (sampleData ? ["-screenshotData"] : []) + [
            "-AppleLanguages", "(en-US)", "-AppleLocale", "en_US",
        ] + arguments
        // Chosen by the workflow so it is evening in the app, whatever time the run starts.
        if let timeZone = ProcessInfo.processInfo.environment["NEWBEE_SCREENSHOT_TZ"], !timeZone.isEmpty {
            app.launchEnvironment["TZ"] = timeZone
        }
        app.launch()
        return app
    }

    /// Lets animations and charts finish drawing.
    func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    @MainActor
    func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let outputDirectory {
            let url = outputDirectory.appendingPathComponent("\(name).png")
            XCTAssertNoThrow(try screenshot.pngRepresentation.write(to: url))
        }
    }
}
