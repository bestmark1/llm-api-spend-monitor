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
        XCTAssertTrue(app.secureTextFields["connection.qwen.secret"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["connection.qwen.endpoint"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["connection.kimi.card"].exists)
        XCTAssertFalse(app.secureTextFields["connection.kimi.secret"].exists)
    }
}
