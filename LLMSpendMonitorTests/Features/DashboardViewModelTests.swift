import XCTest
@testable import LLMSpendMonitor

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testCachePublishesBeforeRefreshAndOfficialTotalIsExact() async throws {
        let cached = try makeCostSnapshot(providerID: .openAI, amount: "1.25")
        let refreshed = try makeCostSnapshot(providerID: .openAI, amount: "2.50")
        let dataSource = DashboardDataSourceStub(
            cached: [.openAI: cached],
            refreshed: [.openAI: refreshed]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            now: { cached.coverage!.through.addingTimeInterval(-1) }
        )

        await model.loadCache()

        XCTAssertEqual(model.snapshots[.openAI], cached)
        XCTAssertEqual(model.officialUSDTotal.amount, Decimal(string: "1.25"))

        await model.refresh(trigger: .manual)

        XCTAssertEqual(model.snapshots[.openAI], refreshed)
        XCTAssertEqual(model.officialUSDTotal.amount, Decimal(string: "2.50"))
    }

    func testAggregateExcludesPartialProviderCosts() async throws {
        let complete = try makeCostSnapshot(providerID: .openAI, amount: "1.25")
        let partial = try makeCostSnapshot(
            providerID: .anthropic,
            amount: "3.00",
            completeness: .partial
        )
        let dataSource = DashboardDataSourceStub(
            cached: [.openAI: complete, .anthropic: partial],
            refreshed: [:]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            now: { complete.coverage!.through.addingTimeInterval(-1) }
        )

        await model.loadCache()

        XCTAssertEqual(model.officialUSDTotal.amount, Decimal(string: "1.25"))
    }

    func testAggregateExcludesErroredProviderCost() async throws {
        let errored = try makeCostSnapshot(
            providerID: .openAI,
            amount: "9.00",
            issue: .providerUnavailable
        )
        let dataSource = DashboardDataSourceStub(cached: [.openAI: errored], refreshed: [:])
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            now: { errored.coverage!.through.addingTimeInterval(-1) }
        )

        await model.loadCache()

        XCTAssertEqual(model.officialUSDTotal.amount, 0)
    }

    func testCredentialChangePurgesOldSnapshotBeforeRefreshing() async throws {
        let cached = try makeCostSnapshot(providerID: .openAI, amount: "4.00")
        let dataSource = DashboardDataSourceStub(
            cached: [.openAI: cached],
            refreshed: [:]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            now: { cached.coverage!.through.addingTimeInterval(-1) }
        )
        await model.loadCache()

        await model.credentialDidChange(.openAI)

        XCTAssertNil(model.snapshots[.openAI])
        let purgedProviders = await dataSource.purgedProviders
        XCTAssertEqual(purgedProviders, [.openAI])
    }

    func testPeriodSelectionFiltersOfficialCostAndProviderSnapshot() async throws {
        let snapshot = try makeDailyCostSnapshot(amounts: ["1.00", "2.00", "3.00"])
        let dataSource = DashboardDataSourceStub(
            cached: [.openAI: snapshot],
            refreshed: [.openAI: snapshot]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            now: { Date(timeIntervalSince1970: 1_700_265_599) }
        )
        await model.loadCache()

        XCTAssertEqual(model.officialUSDTotal.amount, Decimal(string: "3.00"))
        XCTAssertEqual(model.snapshot(for: .openAI)?.buckets.count, 1)

        model.selectedPeriod = .yesterday
        XCTAssertEqual(model.officialUSDTotal.amount, Decimal(string: "2.00"))

        model.selectedPeriod = .thirtyDays
        XCTAssertEqual(model.officialUSDTotal.amount, Decimal(string: "6.00"))
        XCTAssertEqual(model.snapshot(for: .openAI)?.buckets.count, 3)
    }

    private func makeCostSnapshot(
        providerID: ProviderID,
        amount: String,
        completeness: ReportingCoverage.Completeness = .complete,
        issue: ProviderIssue? = nil
    ) throws -> ProviderSnapshot {
        let start = Date(timeIntervalSince1970: 1_700_006_400)
        let end = start.addingTimeInterval(86_400)
        let metric = MoneyMetric(
            value: try Money(amount: Decimal(string: amount)!, currencyCode: "USD"),
            provenance: .official
        )
        return try ProviderSnapshot(
            providerID: providerID,
            capabilities: [.officialCostHistory],
            fetchedAt: end,
            coverage: ReportingCoverage(start: start, through: end, completeness: completeness),
            buckets: [PeriodBucket(start: start, end: end, cost: metric)],
            balances: [],
            issue: issue
        )
    }

    private func makeDailyCostSnapshot(amounts: [String]) throws -> ProviderSnapshot {
        let start = Date(timeIntervalSince1970: 1_700_006_400)
        let buckets = try amounts.enumerated().map { index, amount in
            let bucketStart = start.addingTimeInterval(TimeInterval(index) * 86_400)
            return PeriodBucket(
                start: bucketStart,
                end: bucketStart.addingTimeInterval(86_400),
                cost: MoneyMetric(
                    value: try Money(
                        amount: Decimal(string: amount)!,
                        currencyCode: "USD"
                    ),
                    provenance: .official
                )
            )
        }
        return try ProviderSnapshot(
            providerID: .openAI,
            capabilities: [.officialCostHistory],
            fetchedAt: buckets.last!.end,
            coverage: ReportingCoverage(
                start: start.addingTimeInterval(-27 * 86_400),
                through: buckets.last!.end,
                completeness: .complete
            ),
            buckets: buckets,
            balances: [],
            issue: nil
        )
    }
}

private actor DashboardDataSourceStub: DashboardDataRefreshing {
    let cached: [ProviderID: ProviderSnapshot]
    let refreshed: [ProviderID: ProviderSnapshot]
    private(set) var purgedProviders: [ProviderID] = []

    init(
        cached: [ProviderID: ProviderSnapshot],
        refreshed: [ProviderID: ProviderSnapshot]
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

    func purge(_ providerID: ProviderID) {
        purgedProviders.append(providerID)
    }
}
