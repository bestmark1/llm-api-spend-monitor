import XCTest
@testable import LLMSpendMonitor

@MainActor
final class MenuBarShellTests: XCTestCase {
    func testApplicationIsConfiguredAsDocklessAgent() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }

    func testApplicationUsesSpenderBrandAssets() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Spender")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, "Spender")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String, "Spender.icns")
        XCTAssertNotNil(Bundle.main.url(forResource: "Spender", withExtension: "icns"))

        let menuBarIcon = SpenderMenuBarIcon.make()
        XCTAssertTrue(menuBarIcon.isTemplate)
        XCTAssertEqual(menuBarIcon.size, NSSize(width: 18, height: 18))
    }

    func testSkippingOnboardingShowsDashboardAndConnectionsRemainReachable() {
        let state = AppState()

        XCTAssertEqual(state.destination, .onboarding)

        state.skipOnboarding()
        XCTAssertEqual(state.destination, .dashboard)

        state.showConnections()
        XCTAssertEqual(state.destination, .connections)

        state.showCustomize()
        XCTAssertEqual(state.destination, .customize)

        state.showDashboard()
        XCTAssertEqual(state.destination, .dashboard)
    }

    func testMenuBarLabelExposesMetricAndAccessibleDescription() {
        XCTAssertEqual(MenuBarLabelView.metricText, "$0.00")
        XCTAssertEqual(MenuBarLabelView.accessibilityLabel, "LLM API spend today: $0.00")

        let total = try! Money(amount: Decimal(string: "12.34")!, currencyCode: "USD")
        XCTAssertEqual(MenuBarLabelView.metricText(for: total), "$12.34")
        XCTAssertEqual(
            MenuBarLabelView.accessibilityLabel(for: total),
            "LLM API spend today: $12.34"
        )
    }

    func testRefreshSchedulerStartsOnlyOnePeriodicLoop() async {
        let sleeper = OneShotSleeper()
        let recorder = RefreshTriggerRecorder()
        let scheduler = RefreshScheduler(
            interval: 300,
            sleep: { interval in try await sleeper.sleep(for: interval) },
            refresh: { trigger in await recorder.record(trigger) }
        )

        scheduler.start()
        scheduler.start()

        for _ in 0..<100 where await recorder.values.isEmpty {
            await Task.yield()
        }
        scheduler.stop()

        let sleepCallCount = await sleeper.currentCallCount()
        let triggers = await recorder.currentValues()
        XCTAssertEqual(sleepCallCount, 2)
        XCTAssertEqual(triggers, [.timer])
    }

    func testRefreshSchedulerForwardsLifecycleTriggers() async {
        let recorder = RefreshTriggerRecorder()
        let scheduler = RefreshScheduler(
            refresh: { trigger in await recorder.record(trigger) }
        )

        await scheduler.refreshNow(for: .panelOpen)
        await scheduler.refreshNow(for: .wake)
        await scheduler.refreshNow(for: .unlock)

        let triggers = await recorder.currentValues()
        XCTAssertEqual(triggers, [.panelOpen, .wake, .unlock])
    }

    func testNotificationSettingsReflectStoredAndDeniedPermissionState() async {
        let service = NotificationSettingsServiceStub(enabled: true, grantOnEnable: false)
        let model = NotificationSettingsViewModel(service: service)

        await model.load()
        XCTAssertTrue(model.isEnabled)

        await model.setEnabled(true)
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.permissionDenied)

        await model.setEnabled(false)
        XCTAssertFalse(model.permissionDenied)
    }

    func testLaunchAtLoginSettingsReflectRegistrationAndApprovalState() {
        let service = LaunchAtLoginServiceStub(status: .requiresApproval)
        let model = LaunchAtLoginSettingsViewModel(service: service)

        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(model.requiresApproval)

        model.setEnabled(false)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.requiresApproval)

        model.setEnabled(true)
        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.requiresApproval)
        XCTAssertEqual(service.requestedStates, [false, true])
    }

    func testMissingLaunchAtLoginServiceStillAttemptsRegistration() {
        XCTAssertTrue(LaunchAtLoginStatus.notRegistered.shouldAttemptRegistration)
        XCTAssertTrue(LaunchAtLoginStatus.notFound.shouldAttemptRegistration)
        XCTAssertFalse(LaunchAtLoginStatus.enabled.shouldAttemptRegistration)
        XCTAssertFalse(LaunchAtLoginStatus.requiresApproval.shouldAttemptRegistration)
    }
}

private actor OneShotSleeper {
    private(set) var callCount = 0

    func sleep(for interval: TimeInterval) throws {
        callCount += 1
        if callCount > 1 {
            throw CancellationError()
        }
    }

    func currentCallCount() -> Int {
        callCount
    }
}

private actor RefreshTriggerRecorder {
    private(set) var values: [RefreshTrigger] = []

    func record(_ trigger: RefreshTrigger) {
        values.append(trigger)
    }

    func currentValues() -> [RefreshTrigger] {
        values
    }
}

private actor NotificationSettingsServiceStub: BalanceNotificationSettingsHandling {
    private var enabled: Bool
    private let grantOnEnable: Bool

    init(enabled: Bool, grantOnEnable: Bool) {
        self.enabled = enabled
        self.grantOnEnable = grantOnEnable
    }

    func isEnabled() -> Bool {
        enabled
    }

    func setEnabled(_ requested: Bool) -> Bool {
        enabled = requested && grantOnEnable
        return enabled
    }
}

@MainActor
private final class LaunchAtLoginServiceStub: LaunchAtLoginHandling {
    private(set) var status: LaunchAtLoginStatus
    private(set) var requestedStates: [Bool] = []

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) {
        requestedStates.append(enabled)
        status = enabled ? .enabled : .notRegistered
    }

    func openSystemSettings() {}
}
