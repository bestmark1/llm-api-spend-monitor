import XCTest
@testable import LLMSpendMonitor

@MainActor
final class MenuBarShellTests: XCTestCase {
    func testApplicationIsConfiguredAsDocklessAgent() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
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
