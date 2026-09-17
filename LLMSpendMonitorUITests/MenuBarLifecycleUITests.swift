import XCTest

@MainActor
final class MenuBarLifecycleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchPresentsOnboardingAndKeepsRunning() {
        let app = makeIsolatedApp()
        app.launch()

        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertTrue(
            app.staticTexts["Every API bill in one place."].waitForExistence(timeout: 5),
            "The first-launch onboarding panel should open automatically."
        )
    }

    func testSettingsExposeStartupAndLowBalanceControls() {
        let app = makeIsolatedApp()
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

    func testDashboardPanelClosesWhenAnotherApplicationActivates() {
        let app = makeIsolatedApp()
        app.launchArguments.append("--dashboard-preview")
        app.launch()

        let heading = app.staticTexts["Spender"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        XCTAssertTrue(
            heading.waitForNonExistence(timeout: 3),
            "The dashboard should close after the user clicks outside Spender."
        )
    }

    func testProviderCardCanExpandFromCompactSummary() {
        let app = makeIsolatedApp(demoData: true)
        app.launchArguments.append("--dashboard-preview")
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
        // Assigning the array would drop --demo-data, and the relaunched app would read
        // card expansion from the standard defaults instead of this test's suite — which
        // is what made this assertion depend on whatever the machine happened to hold.
        app.launchArguments = ["--dashboard-preview", "--demo-data"]
        app.launch()

        let restoredDisclosure = app.buttons["provider.openai.disclosure"]
        XCTAssertTrue(restoredDisclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredDisclosure.value as? String, "Expanded")

        // The expanded OpenAI card pushes Anthropic below the panel, and the list only
        // mounts the cards it can show. Scrolling it into the hierarchy is what the
        // assertion is about — the stored expansion state, not what happens to fit.
        let untouchedDisclosure = app.buttons["provider.anthropic.disclosure"]
        scrollUntilPresent(untouchedDisclosure, in: app.scrollViews.firstMatch)
        XCTAssertTrue(untouchedDisclosure.exists)
        XCTAssertEqual(untouchedDisclosure.value as? String, "Collapsed")
    }

    func testProviderCardsExposeDragHandle() {
        let app = makeIsolatedApp()
        app.launchArguments.append("--dashboard-preview")
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["provider.openai.dragHandle"]
                .waitForExistence(timeout: 5)
        )
    }

    func testThirtyDaySummaryShowsProvenanceAndTrend() {
        let app = makeIsolatedApp(demoData: true)
        app.launchArguments.append("--dashboard-preview")
        app.launch()

        // The panel sizes itself to its content, and its content arrives after the
        // first refresh returns. Clicking before then resolves a control against a
        // panel that is about to resize, and the click lands nowhere.
        XCTAssertTrue(
            app.descendants(matching: .any)["dashboard.compactProviderLegend"]
                .waitForExistence(timeout: 5)
        )

        let thirtyDays = app.descendants(matching: .any)["30 Days"]
        XCTAssertTrue(thirtyDays.waitForExistence(timeout: 5))
        thirtyDays.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["dashboard.summary.provenance"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["dashboard.spendTrend"]
                .waitForExistence(timeout: 3)
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Thirty-day spend provenance and trend"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testCustomizeOmitsUnsupportedProvidersAndCanShowAvailableProvider() {
        let app = makeIsolatedApp()
        let suiteName = "com.bestmark.SpenderUITests.\(UUID().uuidString)"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            app.terminate()
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        app.launchArguments.append(contentsOf: [
            "--dashboard-preview",
            "--reset-provider-card-expansion"
        ])
        app.launchEnvironment["SPENDER_CUSTOMIZATION_SUITE"] = suiteName
        app.launch()

        app.menuButtons["Options"].click()
        app.menuItems["Customize"].click()

        let geminiToggle = app.descendants(matching: .any)["customize.gemini.visible"]
        let perplexityToggle = app.descendants(matching: .any)["customize.perplexity.visible"]
        let kimiToggle = app.descendants(matching: .any)["customize.kimi.visible"]
        XCTAssertTrue(geminiToggle.waitForNonExistence(timeout: 1))
        XCTAssertTrue(perplexityToggle.waitForNonExistence(timeout: 1))
        XCTAssertTrue(kimiToggle.waitForExistence(timeout: 3))

        kimiToggle.click()

        let customizationScreenshot = XCTAttachment(screenshot: app.screenshot())
        customizationScreenshot.name = "Provider visibility options"
        customizationScreenshot.lifetime = .keepAlways
        add(customizationScreenshot)

        app.buttons["Back"].click()

        XCTAssertTrue(
            app.descendants(matching: .any)["provider.gemini.card"]
                .waitForNonExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["provider.perplexity.card"]
                .waitForNonExistence(timeout: 3)
        )
        let dashboardScroll = app.scrollViews.firstMatch
        let kimiCard = app.descendants(matching: .any)["provider.kimi.card"]
        scrollUntilVisible(kimiCard, in: dashboardScroll)
        XCTAssertTrue(kimiCard.exists)

        app.buttons["provider.kimi.disclosure"].click()
        XCTAssertTrue(
            app.staticTexts["Connect this provider to load official data."]
                .waitForExistence(timeout: 3)
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Optional available provider"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Scrolls down only until `element` is in the hierarchy, then stops.
    ///
    /// The dashboard mounts provider cards lazily, so a card below the fold is absent
    /// rather than merely off-screen. Waiting for `isHittable` instead would keep
    /// swiping past a card that is already present, unmounting it again.
    private func scrollUntilPresent(
        _ element: XCUIElement,
        in container: XCUIElement,
        attempts: Int = 10
    ) {
        for _ in 0..<attempts {
            if element.exists { return }
            container.swipeUp()
        }
    }

    private func scrollUntilVisible(
        _ element: XCUIElement,
        in container: XCUIElement,
        attempts: Int = 10
    ) {
        for _ in 0..<attempts where !element.exists || !element.isHittable {
            container.swipeUp()
        }
    }

    /// An app instance whose persistence is scoped to this test.
    ///
    /// `demoData` swaps the refresh coordinator for fixed fictional snapshots, so a
    /// test that needs provider metrics gets them without a Keychain credential or a
    /// network call. Without it the app has no snapshots on a machine with no
    /// connected provider, and anything that renders from one is simply absent.
    private func makeIsolatedApp(demoData: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        let token = UUID().uuidString
        let balanceSuite = "com.bestmark.SpenderUITests.Balances.\(token)"
        let customizationSuite = "com.bestmark.SpenderUITests.Customization.\(token)"
        let balanceDefaults = UserDefaults(suiteName: balanceSuite)
        let customizationDefaults = UserDefaults(suiteName: customizationSuite)
        balanceDefaults?.removePersistentDomain(forName: balanceSuite)
        customizationDefaults?.removePersistentDomain(forName: customizationSuite)
        app.launchEnvironment["SPENDER_PLATFORM_BALANCE_SUITE"] = balanceSuite
        app.launchEnvironment["SPENDER_CUSTOMIZATION_SUITE"] = customizationSuite
        if demoData {
            app.launchArguments.append("--demo-data")
        }
        addTeardownBlock {
            app.terminate()
            balanceDefaults?.removePersistentDomain(forName: balanceSuite)
            customizationDefaults?.removePersistentDomain(forName: customizationSuite)
        }
        return app
    }

}
