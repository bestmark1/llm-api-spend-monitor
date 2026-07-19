import XCTest
@testable import LLMSpendMonitor

final class BalanceNotificationServiceTests: XCTestCase {
    func testAuthorizationIsPersistedOnlyWhenGranted() async {
        let preferences = NotificationPreferenceStoreStub()
        let deniedClient = NotificationClientStub(authorizationGranted: false)
        let deniedService = BalanceNotificationService(
            preferences: preferences,
            deliveries: NotificationDeliveryStoreStub(),
            client: deniedClient
        )

        let denied = await deniedService.setEnabled(true)
        let deniedPreference = await preferences.enabledValue()
        XCTAssertFalse(denied)
        XCTAssertFalse(deniedPreference)

        let grantedClient = NotificationClientStub(authorizationGranted: true)
        let grantedService = BalanceNotificationService(
            preferences: preferences,
            deliveries: NotificationDeliveryStoreStub(),
            client: grantedClient
        )

        let granted = await grantedService.setEnabled(true)
        let grantedPreference = await preferences.enabledValue()
        let authorizationRequests = await grantedClient.authorizationRequestCount()
        XCTAssertTrue(granted)
        XCTAssertTrue(grantedPreference)
        XCTAssertEqual(authorizationRequests, 1)
    }

    func testWarningAndCriticalAlertsAreDeliveredOncePerCalibration() async throws {
        let client = NotificationClientStub(authorizationGranted: true)
        let service = BalanceNotificationService(
            preferences: NotificationPreferenceStoreStub(enabled: true),
            deliveries: NotificationDeliveryStoreStub(),
            client: client
        )
        let firstCalibration = Date(timeIntervalSince1970: 2_000_000_000)

        await service.evaluate([.openAI: try status(remaining: 19, synchronizedAt: firstCalibration)])
        await service.evaluate([.openAI: try status(remaining: 19, synchronizedAt: firstCalibration)])
        await service.evaluate([.openAI: try status(remaining: 4, synchronizedAt: firstCalibration)])
        await service.evaluate([.openAI: try status(remaining: 4, synchronizedAt: firstCalibration)])

        var alerts = await client.deliveredAlerts()
        XCTAssertEqual(alerts.map(\.level), [.warning, .critical])

        let nextCalibration = firstCalibration.addingTimeInterval(3_600)
        await service.evaluate([.openAI: try status(remaining: 19, synchronizedAt: nextCalibration)])

        alerts = await client.deliveredAlerts()
        XCTAssertEqual(alerts.map(\.level), [.warning, .critical, .warning])
    }

    func testFirstObservationBelowCriticalThresholdSkipsWarning() async throws {
        let client = NotificationClientStub(authorizationGranted: true)
        let service = BalanceNotificationService(
            preferences: NotificationPreferenceStoreStub(enabled: true),
            deliveries: NotificationDeliveryStoreStub(),
            client: client
        )

        await service.evaluate([
            .anthropic: try status(
                remaining: 2,
                synchronizedAt: Date(timeIntervalSince1970: 2_000_000_000)
            )
        ])

        let levels = await client.deliveredAlerts().map(\.level)
        XCTAssertEqual(levels, [.critical])
    }

    func testConcurrentEvaluationsDoNotDeliverDuplicates() async throws {
        let client = NotificationClientStub(
            authorizationGranted: true,
            deliveryDelayNanoseconds: 100_000_000
        )
        let service = BalanceNotificationService(
            preferences: NotificationPreferenceStoreStub(enabled: true),
            deliveries: NotificationDeliveryStoreStub(),
            client: client
        )
        let balance = try status(
            remaining: 19,
            synchronizedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )

        async let first: Void = service.evaluate([.openAI: balance])
        async let second: Void = service.evaluate([.openAI: balance])
        _ = await (first, second)

        let alerts = await client.deliveredAlerts()
        XCTAssertEqual(alerts.count, 1)
    }

    private func status(
        remaining: Decimal,
        synchronizedAt: Date
    ) throws -> PlatformBalanceStatus {
        PlatformBalanceStatus(
            calibratedBalance: try Money(amount: 100, currencyCode: "USD"),
            remaining: try Money(amount: remaining, currencyCode: "USD"),
            deductedSpend: try Money(amount: 100 - remaining, currencyCode: "USD"),
            synchronizedAt: synchronizedAt,
            automaticallyDeductsSpend: true
        )
    }
}

private actor NotificationPreferenceStoreStub: BalanceNotificationPreferenceStoring {
    private var enabled: Bool

    init(enabled: Bool = false) {
        self.enabled = enabled
    }

    func isEnabled() -> Bool { enabled }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    func enabledValue() -> Bool { enabled }
}

private actor NotificationDeliveryStoreStub: BalanceNotificationDeliveryStoring {
    private var identifiers: Set<String> = []

    func contains(_ identifier: String) -> Bool { identifiers.contains(identifier) }
    func insert(_ identifier: String) { identifiers.insert(identifier) }
}

private actor NotificationClientStub: BalanceNotificationClient {
    private let authorizationGranted: Bool
    private let deliveryDelayNanoseconds: UInt64
    private var authorizationRequests = 0
    private var alerts: [BalanceAlert] = []

    init(
        authorizationGranted: Bool,
        deliveryDelayNanoseconds: UInt64 = 0
    ) {
        self.authorizationGranted = authorizationGranted
        self.deliveryDelayNanoseconds = deliveryDelayNanoseconds
    }

    func requestAuthorization() -> Bool {
        authorizationRequests += 1
        return authorizationGranted
    }

    func deliver(_ alert: BalanceAlert) async throws {
        if deliveryDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: deliveryDelayNanoseconds)
        }
        alerts.append(alert)
    }

    func authorizationRequestCount() -> Int { authorizationRequests }
    func deliveredAlerts() -> [BalanceAlert] { alerts }
}
