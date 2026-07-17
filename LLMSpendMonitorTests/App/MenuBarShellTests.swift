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
}
