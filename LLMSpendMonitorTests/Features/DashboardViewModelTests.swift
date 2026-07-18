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
        XCTAssertTrue(model.isOfficialCostPartial)
        XCTAssertEqual(model.excludedOfficialCostProviderCount, 1)
    }

    func testAggregateProvidesOfficialProviderBreakdown() async throws {
        let openAI = try makeCostSnapshot(providerID: .openAI, amount: "1.25")
        let anthropic = try makeCostSnapshot(providerID: .anthropic, amount: "2.75")
        let dataSource = DashboardDataSourceStub(
            cached: [.openAI: openAI, .anthropic: anthropic],
            refreshed: [:]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            now: { openAI.coverage!.through.addingTimeInterval(-1) }
        )

        await model.loadCache()

        XCTAssertEqual(model.officialUSDTotal.amount, Decimal(string: "4.00"))
        XCTAssertEqual(model.officialUSDBreakdown.map(\.providerID), [.anthropic, .openAI])
        XCTAssertEqual(
            model.officialUSDBreakdown.map(\.amount.amount),
            [Decimal(string: "2.75"), Decimal(string: "1.25")]
        )
        XCTAssertFalse(model.isOfficialCostPartial)
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

    func testDailySpendAggregatesProvidersByUTCDay() async throws {
        let openAI = try makeDailyCostSnapshot(
            providerID: .openAI,
            amounts: ["1.00", "2.00", "3.00"]
        )
        let anthropic = try makeDailyCostSnapshot(
            providerID: .anthropic,
            amounts: ["0.50", "1.50", "2.50"]
        )
        let dataSource = DashboardDataSourceStub(
            cached: [.openAI: openAI, .anthropic: anthropic],
            refreshed: [:]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            now: { Date(timeIntervalSince1970: 1_700_265_599) }
        )
        model.selectedPeriod = .thirtyDays

        await model.loadCache()

        XCTAssertEqual(
            model.officialUSDDailySpend.map(\.amount.amount),
            [Decimal(string: "1.50"), Decimal(string: "3.50"), Decimal(string: "5.50")]
        )
    }

    func testTargetedRefreshFetchesOnlyRequestedProvider() async throws {
        let snapshot = try makeCostSnapshot(providerID: .openAI, amount: "1.00")
        let dataSource = DashboardDataSourceStub(
            cached: [:],
            refreshed: [.openAI: snapshot]
        )
        let targets = [
            makeTarget(.openAI),
            makeTarget(.anthropic)
        ]
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: targets,
            now: { snapshot.coverage!.through.addingTimeInterval(-1) }
        )

        await model.refresh(trigger: .manual, providerID: .openAI)

        let requests = await dataSource.refreshTargetIDs
        XCTAssertEqual(requests, [[.openAI]])
    }

    func testMenuBarTotalUsesTodayRegardlessOfSelectedDashboardPeriod() async throws {
        let snapshot = try makeDailyCostSnapshot(amounts: ["2.00", "3.00"])
        let dataSource = DashboardDataSourceStub(
            cached: [.openAI: snapshot],
            refreshed: [:]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            now: { snapshot.buckets[1].start.addingTimeInterval(3_600) }
        )
        model.selectedPeriod = .yesterday

        await model.loadCache()

        XCTAssertEqual(model.officialUSDTotal.amount, Decimal(string: "2.00"))
        XCTAssertEqual(model.menuBarUSDTotal.amount, Decimal(string: "3.00"))
    }

    func testProviderFreshnessDistinguishesCurrentProcessingAndStaleData() async throws {
        let current = try makeCostSnapshot(providerID: .openAI, amount: "1.00")
        let processing = try makeProcessingSnapshot(providerID: .anthropic, fetchedAt: current.fetchedAt)
        let dataSource = DashboardDataSourceStub(
            cached: [.openAI: current, .anthropic: processing],
            refreshed: [:]
        )
        let model = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            now: { current.fetchedAt.addingTimeInterval(60) }
        )

        await model.loadCache()

        XCTAssertEqual(model.providerFreshness(for: .openAI), .current)
        XCTAssertEqual(model.providerFreshness(for: .anthropic), .processing)

        let staleModel = DashboardViewModel(
            dataSource: dataSource,
            targets: [],
            now: { current.fetchedAt.addingTimeInterval(30 * 60 + 1) }
        )
        await staleModel.loadCache()

        XCTAssertEqual(staleModel.providerFreshness(for: .openAI), .stale)
    }

    private func makeTarget(_ providerID: ProviderID) -> ProviderRefreshTarget {
        ProviderRefreshTarget(
            providerID: providerID,
            generation: 0,
            minimumInterval: 0,
            automaticRefreshEnabled: true,
            fetch: { throw ProviderClientError.unavailable },
            generationIsCurrent: { _ in true }
        )
    }

    private func makeProcessingSnapshot(
        providerID: ProviderID,
        fetchedAt: Date
    ) throws -> ProviderSnapshot {
        let start = fetchedAt.addingTimeInterval(-86_400)
        return try ProviderSnapshot(
            providerID: providerID,
            capabilities: [.officialCostHistory, .tokenUsage],
            fetchedAt: fetchedAt,
            coverage: ReportingCoverage(start: start, through: fetchedAt, completeness: .complete),
            buckets: [
                PeriodBucket(
                    start: start,
                    end: fetchedAt,
                    tokenUsage: TokenUsage(
                        inputTokens: 10,
                        outputTokens: 5,
                        cachedInputTokens: 0,
                        provenance: .official
                    )
                )
            ],
            balances: [],
            issue: nil
        )
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

    private func makeDailyCostSnapshot(
        providerID: ProviderID = .openAI,
        amounts: [String]
    ) throws -> ProviderSnapshot {
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
            providerID: providerID,
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
    private(set) var refreshTargetIDs: [[ProviderID]] = []

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
        refreshTargetIDs.append(targets.map(\.providerID))
        return refreshed
    }

    func purge(_ providerID: ProviderID) {
        purgedProviders.append(providerID)
    }
}
