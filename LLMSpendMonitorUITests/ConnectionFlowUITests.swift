import XCTest

@MainActor
final class ConnectionFlowUITests: XCTestCase {
    func testConnectionsExposeMaskedCredentialControls() {
        let app = XCUIApplication()
        app.launchArguments.append("--keep-panel-open")
        app.launch()

        app.buttons["Connect Provider"].click()

        XCTAssertTrue(app.secureTextFields["connection.openai.secret"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connection.openai.save"].exists)
    }
}
