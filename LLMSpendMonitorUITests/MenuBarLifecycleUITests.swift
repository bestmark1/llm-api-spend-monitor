import XCTest

@MainActor
final class MenuBarLifecycleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchPresentsOnboardingAndKeepsRunning() {
        let app = XCUIApplication()
        app.launchArguments.append("--keep-panel-open")
        app.launch()

        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertTrue(
            app.staticTexts["Monitor your LLM API spend"].waitForExistence(timeout: 5),
            "The first-launch onboarding panel should open automatically."
        )
    }

}
