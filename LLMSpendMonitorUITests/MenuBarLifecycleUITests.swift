import XCTest

@MainActor
final class MenuBarLifecycleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchPresentsOnboardingAndKeepsRunning() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertTrue(
            app.staticTexts["Monitor your LLM API spend"].waitForExistence(timeout: 5),
            "The first-launch onboarding panel should open automatically."
        )
    }

    func testSettingsExposeLowBalanceAlerts() {
        let app = XCUIApplication()
        app.launchArguments.append("--dashboard-preview")
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

    func testDashboardPanelRemainsVisibleWhenAnotherApplicationActivates() {
        let app = XCUIApplication()
        app.launchArguments.append("--dashboard-preview")
        app.launch()

        let heading = app.staticTexts["LLM Spend"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))

        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()

        XCTAssertTrue(
            heading.waitForExistence(timeout: 3),
            "The dashboard should remain visible until the user closes it."
        )
    }

}
