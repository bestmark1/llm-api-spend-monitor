import XCTest

@MainActor
final class ConnectionFlowUITests: XCTestCase {
    func testConnectionsExposeMaskedCredentialControls() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Connect Provider"].click()

        XCTAssertTrue(app.secureTextFields["connection.openai.secret"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connection.openai.save"].exists)

        app.scrollViews.firstMatch.swipeUp()
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

        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.textFields["connection.qwen.billingAccessKeyID"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["connection.qwen.billingAccessKeySecret"].exists)
        XCTAssertTrue(app.textFields["connection.qwen.billingProductCode"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["connection.kimi.card"].exists)
        XCTAssertFalse(app.secureTextFields["connection.kimi.secret"].exists)
    }
}
