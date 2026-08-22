import XCTest

@MainActor
final class ConnectionFlowUITests: XCTestCase {
    func testConnectionsExposeMaskedCredentialControls() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Connect Provider"].click()

        XCTAssertTrue(app.secureTextFields["connection.openai.secret"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connection.openai.save"].exists)

        let scrollView = app.scrollViews.firstMatch
        scrollView.swipeUp()
        let qwenSecret = app.secureTextFields["connection.qwen.secret"]
        XCTAssertTrue(qwenSecret.waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["connection.qwen.endpoint"].exists)
        qwenSecret.click()
        qwenSecret.typeText("sk-sp-ui-test-plan-key")
        XCTAssertTrue(app.staticTexts["connection.qwen.secretError"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["connection.qwen.save"].isEnabled)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Qwen Token Plan rejection"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        scrollView.swipeUp()
        XCTAssertTrue(app.textFields["connection.qwen.billingAccessKeyID"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["connection.qwen.billingAccessKeySecret"].exists)
        XCTAssertTrue(app.textFields["connection.qwen.billingProductCode"].exists)

        for providerID in ["kimi", "xai", "mistral", "openrouter"] {
            let field = app.secureTextFields["connection.\(providerID).secret"]
            scrollUntilVisible(field, in: scrollView)
            XCTAssertTrue(field.exists, "\(providerID) should expose a secure credential field")
        }

        XCTAssertFalse(app.descendants(matching: .any)["connection.gemini.card"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["connection.perplexity.card"].exists)
    }

    private func scrollUntilVisible(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        attempts: Int = 8
    ) {
        for _ in 0..<attempts where !element.exists || !element.isHittable {
            scrollView.swipeUp()
        }
    }
}
