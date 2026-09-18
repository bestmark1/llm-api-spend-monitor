import XCTest

@MainActor
final class ConnectionFlowUITests: XCTestCase {
    func testConnectionsExposeMaskedCredentialControls() {
        let app = XCUIApplication()
        let token = UUID().uuidString
        let suiteName = "com.bestmark.SpenderUITests.Balances.\(token)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        app.launchEnvironment["SPENDER_PLATFORM_BALANCE_SUITE"] = suiteName
        app.launchEnvironment["SPENDER_CUSTOMIZATION_SUITE"] =
            "com.bestmark.SpenderUITests.Customization.\(token)"
        // Keeps credential reads out of the Keychain, so macOS never raises an
        // access prompt that would block the app's main thread mid-test.
        app.launchArguments.append("--demo-data")
        addTeardownBlock {
            app.terminate()
            defaults?.removePersistentDomain(forName: suiteName)
        }
        app.launch()

        app.buttons["Connect Provider"].click()

        XCTAssertTrue(app.secureTextFields["connection.openai.secret"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connection.openai.save"].exists)

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3))

        // The list only scrolls downwards here, so providers are checked in the order
        // ProviderRegistry.userFacing puts them in. Kimi sits above Qwen: looking for it
        // after scrolling past Qwen can never succeed.
        for providerID in ["anthropic", "deepseek", "kimi", "qwen", "xai", "mistral", "openrouter"] {
            let field = app.secureTextFields["connection.\(providerID).secret"]
            scrollUntilPresent(field, in: scrollView)
            XCTAssertTrue(field.exists, "\(providerID) should expose a secure credential field")

            // Providers whose key is not an ordinary inference key say where to
            // create it. Losing one of these links would leave a person holding the
            // wrong kind of key with nothing on screen to tell them so.
            if let guide = [
                "xai": "connection.xai.managementKeyGuide",
                "mistral": "connection.mistral.adminKeyGuide",
                "openrouter": "connection.openrouter.managementKeyGuide"
            ][providerID] {
                XCTAssertTrue(
                    app.links[guide].exists,
                    "\(providerID) should link to instructions for creating its key"
                )
            }

            guard providerID == "qwen" else { continue }

            // Qwen is the only provider carrying an API host and separate billing keys.
            XCTAssertTrue(app.textFields["connection.qwen.endpoint"].exists)
            let productCode = app.textFields["connection.qwen.billingProductCode"]
            scrollUntilPresent(productCode, in: scrollView)
            XCTAssertTrue(app.textFields["connection.qwen.billingAccessKeyID"].exists)
            XCTAssertTrue(app.secureTextFields["connection.qwen.billingAccessKeySecret"].exists)
            XCTAssertTrue(productCode.exists)
        }

        // Token Plan rejection is not exercised here on purpose. Focusing a SecureField
        // under UI automation puts macOS into secure event input and wedges the app's
        // main run loop, so the assertion could never be reached. The same contract —
        // the error message, the disabled Save, the untouched stored key — is covered
        // deterministically by ConnectionViewModelTests.

        let screenshot = XCTAttachment(screenshot: app.windowScreenshot)
        screenshot.name = "Connections list"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertFalse(app.descendants(matching: .any)["connection.gemini.card"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["connection.perplexity.card"].exists)
    }

    /// Scrolls down only until `element` is in the hierarchy, then stops.
    ///
    /// The list materialises provider cards lazily as it scrolls, and scrolling past a
    /// card drops it again. Waiting for `isHittable` would swipe to the bottom every
    /// time an element was present but off-screen, unmounting the very card the caller
    /// is about to assert on.
    private func scrollUntilPresent(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        attempts: Int = 12
    ) {
        for _ in 0..<attempts {
            if element.exists { return }
            scrollView.swipeUp()
        }
    }
}
