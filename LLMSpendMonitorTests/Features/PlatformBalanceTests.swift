import XCTest
@testable import LLMSpendMonitor

private let platformBalanceDayStart = Date(timeIntervalSince1970: 1_700_006_400)
private let platformBalanceSyncDate = platformBalanceDayStart.addingTimeInterval(43_200)

@MainActor
final class PlatformBalanceTests: XCTestCase {
    func testBalanceInputAcceptsDotAndCommaDecimals() throws {
        XCTAssertEqual(
            try PlatformBalanceInput.money(from: " 12.50 ", currencyCode: "USD").amount,
            Decimal(string: "12.50")
        )
        XCTAssertEqual(
            try PlatformBalanceInput.money(from: "12,50", currencyCode: "USD").amount,
            Decimal(string: "12.50")
        )
    }

    func testBalanceInputRejectsEmptyNegativeAndAmbiguousAmounts() {
        for value in ["", "-1", ".", ",", "1,000.00", "1.234", "1234567890123", "hello"] {
            XCTAssertThrowsError(
                try PlatformBalanceInput.money(from: value, currencyCode: "USD"),
                "Expected \(value) to be rejected"
            )
        }
    }

    func testRecalibrationPrefillsCurrentCalculatedBalance() throws {
        let status = PlatformBalanceStatus(
            calibratedBalance: try Money(amount: 100, currencyCode: "USD"),
            remaining: try Money(amount: Decimal(string: "19.25")!, currencyCode: "USD"),
            deductedSpend: try Money(amount: Decimal(string: "80.75")!, currencyCode: "USD"),
            synchronizedAt: platformBalanceSyncDate,
            automaticallyDeductsSpend: true
        )

        XCTAssertEqual(PlatformBalanceInput.prefill(for: status), "19.25")
    }

    func testSynchronizingStartsFromEnteredBalanceWithoutSubtractingEarlierSpend() async throws {
        let store = InMemoryPlatformBalanceStore()
        let snapshot = try makeSnapshot(firstDay: "15.00")
        let model = DashboardViewModel(
            dataSource: DashboardDataSourceStubForBalance(
                cached: [.openAI: snapshot],
                refreshed: [.openAI: snapshot]
            ),
            targets: [],
            platformBalanceStore: store,
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()

        let synchronized = await model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD")
        )
        XCTAssertTrue(synchronized)

        let balance = try XCTUnwrap(model.platformBalance(for: .openAI))
        XCTAssertEqual(balance.remaining.amount, 100)
        XCTAssertEqual(balance.deductedSpend.amount, 0)
        XCTAssertEqual(balance.synchronizedAt, platformBalanceSyncDate)
        XCTAssertTrue(balance.automaticallyDeductsSpend)
    }

    func testReconcileSubtractsOnlySpendObservedAfterSynchronization() async throws {
        let initial = try makeSnapshot(firstDay: "15.00")
        let refreshed = try makeSnapshot(firstDay: "17.00", secondDay: "4.00")
        let dataSource = SequencedDashboardDataSourceForBalance(
            cached: [.openAI: initial],
            refreshes: [
                [.openAI: initial],
                [.openAI: refreshed]
            ]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore(),
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()
        _ = await model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD")
        )

        await model.refresh(trigger: .manual)

        let balance = try XCTUnwrap(model.platformBalance(for: .openAI))
        XCTAssertEqual(balance.deductedSpend.amount, 6)
        XCTAssertEqual(balance.remaining.amount, 94)
    }

    func testFirstSpendLaterOnSynchronizationDayIsDeducted() async throws {
        let initial = try makeEmptySnapshot()
        let refreshed = try makeSnapshot(firstDay: "4.00")
        let dataSource = SequencedDashboardDataSourceForBalance(
            cached: [.openAI: initial],
            refreshes: [
                [.openAI: initial],
                [.openAI: refreshed]
            ]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore(),
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()
        _ = await model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD")
        )

        await model.refresh(trigger: .manual)

        XCTAssertEqual(model.platformBalance(for: .openAI)?.remaining.amount, 96)
    }

    func testSynchronizationRefreshesStaleCostBaselineBeforeSavingBalance() async throws {
        let initial = try makeSnapshot(firstDay: "15.00")
        let refreshed = try makeSnapshot(firstDay: "17.00")
        let model = DashboardViewModel(
            dataSource: DashboardDataSourceStubForBalance(
                cached: [.openAI: initial],
                refreshed: [.openAI: refreshed]
            ),
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore(),
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()
        _ = await model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD")
        )

        await model.refresh(trigger: .manual)

        XCTAssertEqual(model.platformBalance(for: .openAI)?.remaining.amount, 100)
    }

    func testRepeatedIdenticalRefreshDoesNotDeductSpendTwice() async throws {
        let initial = try makeSnapshot(firstDay: "15.00")
        let refreshed = try makeSnapshot(firstDay: "17.00")
        let model = DashboardViewModel(
            dataSource: SequencedDashboardDataSourceForBalance(
                cached: [.openAI: initial],
                refreshes: [
                    [.openAI: initial],
                    [.openAI: refreshed],
                    [.openAI: refreshed]
                ]
            ),
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore(),
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()
        _ = await model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD")
        )

        await model.refresh(trigger: .manual)
        await model.refresh(trigger: .manual)

        XCTAssertEqual(model.platformBalance(for: .openAI)?.remaining.amount, 98)
    }

    func testReportCorrectionIsAppliedBeforeLaterGrowth() async throws {
        let initial = try makeSnapshot(firstDay: "15.00")
        let dataSource = SequencedDashboardDataSourceForBalance(
            cached: [.openAI: initial],
            refreshes: [
                [.openAI: initial],
                [.openAI: try makeSnapshot(firstDay: "17.00")],
                [.openAI: try makeSnapshot(firstDay: "14.00")],
                [.openAI: try makeSnapshot(firstDay: "16.00")]
            ]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore(),
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()
        _ = await model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD")
        )

        await model.refresh(trigger: .manual)
        await model.refresh(trigger: .manual)
        await model.refresh(trigger: .manual)

        let balance = try XCTUnwrap(model.platformBalance(for: .openAI))
        XCTAssertEqual(balance.deductedSpend.amount, 1)
        XCTAssertEqual(balance.remaining.amount, 99)
    }

    func testTemporarilyMissingBucketIsNotDeductedAgainWhenItReturns() async throws {
        let initial = try makeSnapshot(firstDay: "15.00")
        let missing = try makeEmptySnapshot()
        let returned = try makeSnapshot(firstDay: "17.00")
        let dataSource = SequencedDashboardDataSourceForBalance(
            cached: [.openAI: initial],
            refreshes: [
                [.openAI: initial],
                [.openAI: returned],
                [.openAI: missing],
                [.openAI: returned]
            ]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore(),
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()
        _ = await model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD")
        )

        await model.refresh(trigger: .manual)
        await model.refresh(trigger: .manual)
        await model.refresh(trigger: .manual)

        XCTAssertEqual(model.platformBalance(for: .openAI)?.remaining.amount, 98)
    }

    func testIncompleteReportsDoNotChangeTrackedBalance() async throws {
        let initial = try makeSnapshot(firstDay: "15.00")
        let partial = try makeSnapshot(firstDay: "25.00", completeness: .partial)
        let dataSource = SequencedDashboardDataSourceForBalance(
            cached: [.openAI: initial],
            refreshes: [
                [.openAI: initial],
                [.openAI: partial]
            ]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore(),
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()
        _ = await model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD")
        )

        await model.refresh(trigger: .manual)

        XCTAssertEqual(model.platformBalance(for: .openAI)?.remaining.amount, 100)
    }

    func testTrackedBalancePersistsAcrossViewModelRecreation() async throws {
        let store = InMemoryPlatformBalanceStore()
        let snapshot = try makeSnapshot(providerID: .anthropic, firstDay: "5.00")
        let firstModel = DashboardViewModel(
            dataSource: DashboardDataSourceStubForBalance(
                refreshed: [.anthropic: snapshot]
            ),
            targets: [],
            platformBalanceStore: store,
            now: { platformBalanceSyncDate }
        )
        _ = await firstModel.synchronizePlatformBalance(
            providerID: .anthropic,
            balance: try Money(amount: 42, currencyCode: "USD")
        )

        let relaunched = DashboardViewModel(
            dataSource: DashboardDataSourceStubForBalance(),
            targets: [],
            platformBalanceStore: store
        )

        XCTAssertEqual(relaunched.platformBalance(for: .anthropic)?.remaining.amount, 42)
        XCTAssertEqual(relaunched.platformBalance(for: .anthropic)?.synchronizedAt, platformBalanceSyncDate)
    }

    func testProvidersWithoutManualBalanceSupportRejectManualBalance() async throws {
        let model = DashboardViewModel(
            dataSource: DashboardDataSourceStubForBalance(),
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore()
        )

        for providerID in [ProviderID.deepSeek, .gemini, .qwen] {
            let synchronized = await model.synchronizePlatformBalance(
                providerID: providerID,
                balance: try Money(amount: 10, currencyCode: "USD")
            )
            XCTAssertFalse(synchronized)
            XCTAssertNil(model.platformBalance(for: providerID))
        }
    }

    func testCredentialChangeClearsTrackedBalance() async throws {
        let snapshot = try makeSnapshot(firstDay: "5.00")
        let model = DashboardViewModel(
            dataSource: DashboardDataSourceStubForBalance(
                refreshed: [.openAI: snapshot]
            ),
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore()
        )
        _ = await model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD")
        )

        await model.credentialDidChange(.openAI)

        XCTAssertNil(model.platformBalance(for: .openAI))
    }

    func testRefreshPublishesReconciledBalanceToNotificationService() async throws {
        let initial = try makeSnapshot(firstDay: "0.00")
        let refreshed = try makeSnapshot(firstDay: "81.00")
        let notifier = BalanceNotifierStub()
        let model = DashboardViewModel(
            dataSource: SequencedDashboardDataSourceForBalance(
                cached: [.openAI: initial],
                refreshes: [
                    [.openAI: initial],
                    [.openAI: refreshed]
                ]
            ),
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore(),
            balanceNotifier: notifier,
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()
        _ = await model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD")
        )

        await model.refresh(trigger: .manual)

        let latest = await notifier.latestBalances()
        XCTAssertEqual(latest[.openAI]?.remaining.amount, 19)
    }

    private func makeSnapshot(
        providerID: ProviderID = .openAI,
        firstDay: String,
        secondDay: String? = nil,
        completeness: ReportingCoverage.Completeness = .complete
    ) throws -> ProviderSnapshot {
        let start = platformBalanceDayStart
        var buckets = [
            try makeBucket(start: start, amount: firstDay)
        ]
        if let secondDay {
            buckets.append(try makeBucket(start: start.addingTimeInterval(86_400), amount: secondDay))
        }
        return try ProviderSnapshot(
            providerID: providerID,
            capabilities: [.officialCostHistory],
            fetchedAt: buckets.last!.end,
            coverage: ReportingCoverage(
                start: start.addingTimeInterval(-29 * 86_400),
                through: buckets.last!.end,
                completeness: completeness
            ),
            buckets: buckets,
            balances: [],
            issue: completeness == .complete ? nil : .partialData
        )
    }

    private func makeEmptySnapshot() throws -> ProviderSnapshot {
        let start = platformBalanceDayStart
        return try ProviderSnapshot(
            providerID: .openAI,
            capabilities: [.officialCostHistory],
            fetchedAt: platformBalanceSyncDate,
            coverage: ReportingCoverage(
                start: start.addingTimeInterval(-29 * 86_400),
                through: start.addingTimeInterval(86_400),
                completeness: .complete
            ),
            buckets: [],
            balances: [],
            issue: nil
        )
    }

    private func makeBucket(start: Date, amount: String) throws -> PeriodBucket {
        PeriodBucket(
            start: start,
            end: start.addingTimeInterval(86_400),
            cost: MoneyMetric(
                value: try Money(
                    amount: Decimal(string: amount)!,
                    currencyCode: "USD"
                ),
                provenance: .official
            )
        )
    }
}

private final class InMemoryPlatformBalanceStore: PlatformBalanceStoring {
    private var checkpoints: [ProviderID: PlatformBalanceCheckpoint] = [:]

    func load() -> [ProviderID: PlatformBalanceCheckpoint] {
        checkpoints
    }

    func save(_ checkpoints: [ProviderID: PlatformBalanceCheckpoint]) {
        self.checkpoints = checkpoints
    }
}

private actor DashboardDataSourceStubForBalance: DashboardDataRefreshing {
    let cached: [ProviderID: ProviderSnapshot]
    let refreshed: [ProviderID: ProviderSnapshot]

    init(
        cached: [ProviderID: ProviderSnapshot] = [:],
        refreshed: [ProviderID: ProviderSnapshot] = [:]
    ) {
        self.cached = cached
        self.refreshed = refreshed
    }

    func loadCachedSnapshots() -> [ProviderID: ProviderSnapshot] {
        cached
    }

    func refresh(
        trigger: RefreshTrigger,
        targets: [ProviderRefreshTarget]
    ) -> [ProviderID: ProviderSnapshot] {
        refreshed
    }

    func purge(_ providerID: ProviderID) {}
}

private actor SequencedDashboardDataSourceForBalance: DashboardDataRefreshing {
    let cached: [ProviderID: ProviderSnapshot]
    var refreshes: [[ProviderID: ProviderSnapshot]]

    init(
        cached: [ProviderID: ProviderSnapshot],
        refreshes: [[ProviderID: ProviderSnapshot]]
    ) {
        self.cached = cached
        self.refreshes = refreshes
    }

    func loadCachedSnapshots() -> [ProviderID: ProviderSnapshot] {
        cached
    }

    func refresh(
        trigger: RefreshTrigger,
        targets: [ProviderRefreshTarget]
    ) -> [ProviderID: ProviderSnapshot] {
        guard !refreshes.isEmpty else { return [:] }
        return refreshes.removeFirst()
    }

    func purge(_ providerID: ProviderID) {}
}

private actor BalanceNotifierStub: BalanceNotificationHandling {
    private var evaluations: [[ProviderID: PlatformBalanceStatus]] = []

    func evaluate(_ balances: [ProviderID: PlatformBalanceStatus]) {
        evaluations.append(balances)
    }

    func latestBalances() -> [ProviderID: PlatformBalanceStatus] {
        evaluations.last ?? [:]
    }
}
