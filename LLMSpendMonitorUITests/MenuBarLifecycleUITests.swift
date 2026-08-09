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

    func testSettingsExposeStartupAndLowBalanceControls() {
        let app = XCUIApplication()
        app.launchArguments.append("--dashboard-preview")
        app.launch()

        app.menuButtons["Options"].click()
        app.menuItems["Settings"].click()

        let launchAtLoginToggle = app.descendants(matching: .any)["settings.launchAtLogin"]
        let notificationsToggle = app.descendants(matching: .any)["settings.balanceNotifications"]
        XCTAssertTrue(launchAtLoginToggle.waitForExistence(timeout: 3))
        XCTAssertTrue(notificationsToggle.waitForExistence(timeout: 3))
        app.buttons["Close"].click()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Startup and notification settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testDashboardPanelRemainsVisibleWhenAnotherApplicationActivates() {
        let app = XCUIApplication()
        app.launchArguments.append("--dashboard-preview")
        app.launch()

        let heading = app.staticTexts["Spender"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))

        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()

        XCTAssertTrue(
            heading.waitForExistence(timeout: 3),
            "The dashboard should remain visible until the user closes it."
        )
    }

    func testProviderCardCanExpandFromCompactSummary() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "--dashboard-preview",
            "--reset-provider-card-expansion"
        ])
        app.launch()

        let disclosure = app.buttons["provider.openai.disclosure"]
        let compactSummary = app.descendants(matching: .any)["provider.openai.summary"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        XCTAssertTrue(compactSummary.waitForExistence(timeout: 2))

        disclosure.click()

        XCTAssertEqual(disclosure.value as? String, "Expanded")
        XCTAssertTrue(compactSummary.waitForNonExistence(timeout: 2))
        XCTAssertTrue(
            app.descendants(matching: .any)["provider.openai.updated"]
                .waitForExistence(timeout: 2)
        )

        app.terminate()
        app.launchArguments = ["--dashboard-preview"]
        app.launch()

        let restoredDisclosure = app.buttons["provider.openai.disclosure"]
        XCTAssertTrue(restoredDisclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredDisclosure.value as? String, "Expanded")

        let untouchedDisclosure = app.buttons["provider.anthropic.disclosure"]
        XCTAssertTrue(untouchedDisclosure.waitForExistence(timeout: 2))
        XCTAssertEqual(untouchedDisclosure.value as? String, "Collapsed")
    }

}
