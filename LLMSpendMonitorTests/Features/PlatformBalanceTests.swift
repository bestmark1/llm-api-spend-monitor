import XCTest
@testable import LLMSpendMonitor

private let platformBalanceSyncDate = Date(timeIntervalSince1970: 1_700_049_600 + 43_200)

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
        for value in ["", "-1", "1,000.00", "hello"] {
            XCTAssertThrowsError(
                try PlatformBalanceInput.money(from: value, currencyCode: "USD"),
                "Expected \(value) to be rejected"
            )
        }
    }

    func testSynchronizingStartsFromEnteredBalanceWithoutSubtractingEarlierSpend() throws {
        let store = InMemoryPlatformBalanceStore()
        let model = DashboardViewModel(
            dataSource: DashboardDataSourceStubForBalance(),
            targets: [],
            platformBalanceStore: store,
            now: { platformBalanceSyncDate }
        )
        let snapshot = try makeSnapshot(firstDay: "15.00")

        XCTAssertTrue(
            model.synchronizePlatformBalance(
                providerID: .openAI,
                balance: try Money(amount: 100, currencyCode: "USD"),
                snapshot: snapshot
            )
        )

        let balance = try XCTUnwrap(model.platformBalance(for: .openAI))
        XCTAssertEqual(balance.remaining.amount, 100)
        XCTAssertEqual(balance.deductedSpend.amount, 0)
        XCTAssertEqual(balance.synchronizedAt, platformBalanceSyncDate)
        XCTAssertTrue(balance.automaticallyDeductsSpend)
    }

    func testReconcileSubtractsOnlySpendObservedAfterSynchronization() async throws {
        let initial = try makeSnapshot(firstDay: "15.00")
        let refreshed = try makeSnapshot(firstDay: "17.00", secondDay: "4.00")
        let dataSource = DashboardDataSourceStubForBalance(
            cached: [.openAI: initial],
            refreshed: [.openAI: refreshed]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore(),
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()
        _ = model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD"),
            snapshot: initial
        )

        await model.refresh(trigger: .manual)

        let balance = try XCTUnwrap(model.platformBalance(for: .openAI))
        XCTAssertEqual(balance.deductedSpend.amount, 6)
        XCTAssertEqual(balance.remaining.amount, 94)
    }

    func testIncompleteReportsDoNotChangeTrackedBalance() async throws {
        let initial = try makeSnapshot(firstDay: "15.00")
        let partial = try makeSnapshot(firstDay: "25.00", completeness: .partial)
        let dataSource = DashboardDataSourceStubForBalance(
            cached: [.openAI: initial],
            refreshed: [.openAI: partial]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore(),
            now: { platformBalanceSyncDate }
        )
        await model.loadCache()
        _ = model.synchronizePlatformBalance(
            providerID: .openAI,
            balance: try Money(amount: 100, currencyCode: "USD"),
            snapshot: initial
        )

        await model.refresh(trigger: .manual)

        XCTAssertEqual(model.platformBalance(for: .openAI)?.remaining.amount, 100)
    }

    func testTrackedBalancePersistsAcrossViewModelRecreation() throws {
        let store = InMemoryPlatformBalanceStore()
        let firstModel = DashboardViewModel(
            dataSource: DashboardDataSourceStubForBalance(),
            targets: [],
            platformBalanceStore: store,
            now: { platformBalanceSyncDate }
        )
        _ = firstModel.synchronizePlatformBalance(
            providerID: .anthropic,
            balance: try Money(amount: 42, currencyCode: "USD"),
            snapshot: nil
        )

        let relaunched = DashboardViewModel(
            dataSource: DashboardDataSourceStubForBalance(),
            targets: [],
            platformBalanceStore: store
        )

        XCTAssertEqual(relaunched.platformBalance(for: .anthropic)?.remaining.amount, 42)
        XCTAssertEqual(relaunched.platformBalance(for: .anthropic)?.synchronizedAt, platformBalanceSyncDate)
    }

    func testDeepSeekRejectsManualBalanceBecauseItsBalanceIsOfficial() throws {
        let model = DashboardViewModel(
            dataSource: DashboardDataSourceStubForBalance(),
            targets: [],
            platformBalanceStore: InMemoryPlatformBalanceStore()
        )

        XCTAssertFalse(
            model.synchronizePlatformBalance(
                providerID: .deepSeek,
                balance: try Money(amount: 10, currencyCode: "USD"),
                snapshot: nil
            )
        )
        XCTAssertNil(model.platformBalance(for: .deepSeek))
    }

    private func makeSnapshot(
        firstDay: String,
        secondDay: String? = nil,
        completeness: ReportingCoverage.Completeness = .complete
    ) throws -> ProviderSnapshot {
        let start = Date(timeIntervalSince1970: 1_700_049_600)
        var buckets = [
            try makeBucket(start: start, amount: firstDay)
        ]
        if let secondDay {
            buckets.append(try makeBucket(start: start.addingTimeInterval(86_400), amount: secondDay))
        }
        return try ProviderSnapshot(
            providerID: .openAI,
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
