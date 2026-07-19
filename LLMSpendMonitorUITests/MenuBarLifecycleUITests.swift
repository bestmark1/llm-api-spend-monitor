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

    func testSettingsExposeLowBalanceAlerts() {
        let app = XCUIApplication()
        app.launchArguments += ["--dashboard-preview", "--keep-panel-open"]
        app.launch()

        app.menuButtons["Options"].click()
        app.menuItems["Settings"].click()

        let toggle = app.descendants(matching: .any)["settings.balanceNotifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        app.buttons["Close"].click()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Low balance notification settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}
