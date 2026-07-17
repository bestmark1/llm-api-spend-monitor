import XCTest

@MainActor
final class MenuBarLifecycleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchPresentsOnboardingAndKeepsRunning() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Monitor your LLM API spend"].waitForExistence(timeout: 5),
            "The first-launch onboarding panel should open automatically."
        )
    }

    func testDashboardOpensProviderCustomization() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["onboarding.skip"].click()

        XCTAssertTrue(app.otherElements["dashboard.root"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["dashboard.summary"].exists)
        XCTAssertTrue(app.segmentedControls["dashboard.period"].exists)

        app.menuButtons["options.menu"].click()
        app.menuItems["Customize"].click()

        XCTAssertTrue(app.otherElements["customize.root"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["customize.openai.row"].exists)
        XCTAssertTrue(app.switches["customize.openai.visible"].exists)
        XCTAssertTrue(app.buttons["customize.openai.moveDown"].exists)
    }
}
