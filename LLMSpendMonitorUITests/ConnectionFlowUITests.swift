import XCTest

@MainActor
final class ConnectionFlowUITests: XCTestCase {
    func testConnectionsExposeMaskedCredentialControls() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["onboarding.connect"].click()

        XCTAssertTrue(app.otherElements["connections.root"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["connection.openai.secret"].exists)
        XCTAssertTrue(app.buttons["connection.openai.save"].exists)
    }
}
