import Foundation

enum DashboardPeriod: Int, CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case thirtyDays

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thirtyDays: "30 Days"
        }
    }

    func interval(containing date: Date) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: date)

        switch self {
        case .today:
            return DateInterval(
                start: today,
                end: calendar.date(byAdding: .day, value: 1, to: today)!
            )
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: today)!
            return DateInterval(start: start, end: today)
        case .thirtyDays:
            let start = calendar.date(byAdding: .day, value: -29, to: today)!
            let end = calendar.date(byAdding: .day, value: 1, to: today)!
            return DateInterval(start: start, end: end)
        }
    }
}

struct ProviderSpendSummary: Identifiable, Equatable, Sendable {
    let providerID: ProviderID
    let amount: Money

    var id: ProviderID { providerID }
}

struct DailySpendPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let amount: Money

    var id: Date { date }
}

struct PlatformBalanceStatus: Equatable, Sendable {
    let remaining: Money
    let deductedSpend: Money
    let synchronizedAt: Date
    let automaticallyDeductsSpend: Bool
}

private struct PlatformBalanceAnchorKey: Hashable {
    let start: Date
    let end: Date
    let currencyCode: String
}

protocol DashboardDataRefreshing: Sendable {
    func loadCachedSnapshots() async -> [ProviderID: ProviderSnapshot]
    func refresh(
        trigger: RefreshTrigger,
        targets: [ProviderRefreshTarget]
    ) async -> [ProviderID: ProviderSnapshot]
    func purge(_ providerID: ProviderID) async
}

extension RefreshCoordinator: DashboardDataRefreshing {}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    @Published private var platformBalanceCheckpoints: [ProviderID: PlatformBalanceCheckpoint]
    @Published private(set) var isRefreshing = false
    @Published var selectedPeriod: DashboardPeriod = .today

    private let dataSource: any DashboardDataRefreshing
    private let fixedTargets: [ProviderRefreshTarget]?
    private let targetFactory: ProviderTargetFactory
    private let platformBalanceStore: any PlatformBalanceStoring
    private let now: @Sendable () -> Date
    private var hasStarted = false

    init(
        dataSource: any DashboardDataRefreshing = RefreshCoordinator(),
        targets: [ProviderRefreshTarget]? = nil,
        targetFactory: ProviderTargetFactory = ProviderTargetFactory(),
        platformBalanceStore: any PlatformBalanceStoring = UserDefaultsPlatformBalanceStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.dataSource = dataSource
        fixedTargets = targets
        self.targetFactory = targetFactory
        self.platformBalanceStore = platformBalanceStore
        platformBalanceCheckpoints = platformBalanceStore.load()
        self.now = now
    }

    var officialUSDTotal: Money {
        let total = officialUSDBreakdown.reduce(into: Decimal.zero) { result, summary in
            result += summary.amount.amount
        }
        return try! Money(amount: total, currencyCode: "USD")
    }

    var officialUSDBreakdown: [ProviderSpendSummary] {
        snapshots.keys.sorted(by: { $0.rawValue < $1.rawValue }).compactMap { providerID in
            guard let snapshot = completeOfficialCostSnapshot(for: providerID) else { return nil }
            let total = officialUSDCosts(in: snapshot).reduce(into: Decimal.zero) { result, cost in
                result += cost.amount
            }
            guard total > 0 else { return nil }
            return ProviderSpendSummary(
                providerID: providerID,
                amount: try! Money(amount: total, currencyCode: "USD")
            )
        }
    }

    var officialUSDDailySpend: [DailySpendPoint] {
        var totals: [Date: Decimal] = [:]
        for providerID in snapshots.keys {
            guard let snapshot = completeOfficialCostSnapshot(for: providerID) else { continue }
            for bucket in snapshot.buckets {
                guard let cost = officialUSDCost(in: bucket) else { continue }
                totals[utcStartOfDay(for: bucket.start), default: 0] += cost.amount
            }
        }
        return totals.keys.sorted().map { date in
            DailySpendPoint(
                date: date,
                amount: try! Money(amount: totals[date, default: 0], currencyCode: "USD")
            )
        }
    }

    var excludedOfficialCostProviderCount: Int {
        snapshots.keys.reduce(into: 0) { result, providerID in
            guard snapshots[providerID]?.capabilities.contains(.officialCostHistory) == true else { return }
            if completeOfficialCostSnapshot(for: providerID) == nil {
                result += 1
            }
        }
    }

    var isOfficialCostPartial: Bool {
        excludedOfficialCostProviderCount > 0
    }

    func snapshot(for providerID: ProviderID) -> ProviderSnapshot? {
        guard let source = snapshots[providerID], let sourceCoverage = source.coverage else {
            return snapshots[providerID]
        }

        let interval = selectedPeriod.interval(containing: now())
        let fullyCovered = sourceCoverage.start <= interval.start
            && sourceCoverage.through >= interval.end
            && sourceCoverage.completeness == .complete
        let completeness: ReportingCoverage.Completeness = fullyCovered ? .complete : .partial
        let issue = source.issue ?? (fullyCovered ? nil : .partialData)

        return try? ProviderSnapshot(
            providerID: source.providerID,
            capabilities: source.capabilities,
            fetchedAt: source.fetchedAt,
            coverage: ReportingCoverage(
                start: interval.start,
                through: interval.end,
                completeness: completeness
            ),
            buckets: source.buckets.filter {
                $0.start >= interval.start && $0.end <= interval.end
            },
            balances: source.balances,
            issue: issue
        )
    }

    @discardableResult
    func synchronizePlatformBalance(
        providerID: ProviderID,
        balance: Money
    ) async -> Bool {
        guard canSynchronizePlatformBalance(for: providerID) else { return false }

        if ProviderRegistry.metadata(for: providerID)?.capabilities.contains(.officialCostHistory) == true {
            guard !isRefreshing else { return false }
            await refresh(trigger: .manual)
            guard hasCompleteCurrentCostCoverage(for: providerID) else { return false }
        }

        let synchronizedAt = now()
        let anchors = synchronizationAnchors(
            in: snapshots[providerID],
            currencyCode: balance.currencyCode,
            synchronizedAt: synchronizedAt
        )
        platformBalanceCheckpoints[providerID] = PlatformBalanceCheckpoint(
            providerID: providerID,
            enteredBalance: balance,
            synchronizedAt: synchronizedAt,
            deductedSpend: try! Money(amount: 0, currencyCode: balance.currencyCode),
            costAnchors: anchors
        )
        persistPlatformBalances()
        return true
    }

    func canSynchronizePlatformBalance(for providerID: ProviderID) -> Bool {
        providerID != .deepSeek
    }

    func platformBalance(for providerID: ProviderID) -> PlatformBalanceStatus? {
        guard let checkpoint = platformBalanceCheckpoints[providerID] else { return nil }
        let remainingAmount = max(
            Decimal.zero,
            checkpoint.enteredBalance.amount - checkpoint.deductedSpend.amount
        )
        return PlatformBalanceStatus(
            remaining: try! Money(
                amount: remainingAmount,
                currencyCode: checkpoint.enteredBalance.currencyCode
            ),
            deductedSpend: checkpoint.deductedSpend,
            synchronizedAt: checkpoint.synchronizedAt,
            automaticallyDeductsSpend: ProviderRegistry.metadata(for: providerID)?
                .capabilities.contains(.officialCostHistory) == true
        )
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await loadCache()
        await refresh(trigger: .launch)
    }

    func loadCache() async {
        snapshots = await dataSource.loadCachedSnapshots()
        reconcilePlatformBalances()
    }

    func refresh(trigger: RefreshTrigger) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        snapshots = await dataSource.refresh(
            trigger: trigger,
            targets: fixedTargets ?? targetFactory.makeTargets()
        )
        reconcilePlatformBalances()
        isRefreshing = false
    }

    func credentialDidChange(_ providerID: ProviderID) async {
        snapshots.removeValue(forKey: providerID)
        if platformBalanceCheckpoints.removeValue(forKey: providerID) != nil {
            persistPlatformBalances()
        }
        await dataSource.purge(providerID)
        await refresh(trigger: .credentialValidation)
    }

    private func completeOfficialCostSnapshot(for providerID: ProviderID) -> ProviderSnapshot? {
        guard
            let snapshot = snapshot(for: providerID),
            snapshot.issue == nil,
            snapshot.capabilities.contains(.officialCostHistory),
            snapshot.coverage?.completeness == .complete
        else { return nil }
        return snapshot
    }

    private func hasCompleteCurrentCostCoverage(for providerID: ProviderID) -> Bool {
        guard
            let snapshot = snapshots[providerID],
            snapshot.issue == nil,
            snapshot.capabilities.contains(.officialCostHistory),
            let coverage = snapshot.coverage,
            coverage.completeness == .complete
        else { return false }

        let currentDay = utcDayInterval(containing: now())
        return coverage.start <= currentDay.start && coverage.through >= currentDay.end
    }

    private func reconcilePlatformBalances() {
        var reconciledCheckpoints = platformBalanceCheckpoints
        var changed = false

        for (providerID, checkpoint) in platformBalanceCheckpoints {
            guard let snapshot = snapshots[providerID] else { continue }
            let reconciled = reconcile(checkpoint, with: snapshot)
            guard reconciled != checkpoint else { continue }
            reconciledCheckpoints[providerID] = reconciled
            changed = true
        }

        if changed {
            platformBalanceCheckpoints = reconciledCheckpoints
            persistPlatformBalances()
        }
    }

    private func reconcile(
        _ checkpoint: PlatformBalanceCheckpoint,
        with snapshot: ProviderSnapshot
    ) -> PlatformBalanceCheckpoint {
        guard
            snapshot.providerID == checkpoint.providerID,
            snapshot.issue == nil,
            snapshot.coverage?.completeness == .complete,
            snapshot.capabilities.contains(.officialCostHistory)
        else { return checkpoint }

        let currentAnchors = preservingMissingAnchorsAsZero(
            officialCostAnchors(
                in: snapshot,
                currencyCode: checkpoint.enteredBalance.currencyCode
            ),
            from: checkpoint.costAnchors,
            coverage: snapshot.coverage
        )
        let previousCosts = checkpoint.costAnchors.reduce(into: [PlatformBalanceAnchorKey: Decimal]()) {
            $0[anchorKey(for: $1)] = $1.cost.amount
        }
        let delta = currentAnchors.reduce(into: Decimal.zero) { result, anchor in
            if let previous = previousCosts[anchorKey(for: anchor)] {
                result += anchor.cost.amount - previous
            } else if anchor.start >= checkpoint.synchronizedAt {
                result += anchor.cost.amount
            }
        }
        let deductedAmount = checkpoint.deductedSpend.amount + delta

        return PlatformBalanceCheckpoint(
            providerID: checkpoint.providerID,
            enteredBalance: checkpoint.enteredBalance,
            synchronizedAt: checkpoint.synchronizedAt,
            deductedSpend: try! Money(
                amount: deductedAmount,
                currencyCode: checkpoint.enteredBalance.currencyCode
            ),
            costAnchors: currentAnchors
        )
    }

    private func officialCostAnchors(
        in snapshot: ProviderSnapshot?,
        currencyCode: String
    ) -> [PlatformBalanceCostAnchor] {
        guard
            let snapshot,
            snapshot.issue == nil,
            snapshot.coverage?.completeness == .complete
        else { return [] }

        return snapshot.buckets.compactMap { bucket in
            guard
                let cost = bucket.cost,
                cost.provenance == .official,
                cost.value.currencyCode == currencyCode
            else { return nil }
            return PlatformBalanceCostAnchor(
                start: bucket.start,
                end: bucket.end,
                cost: cost.value
            )
        }
    }

    private func synchronizationAnchors(
        in snapshot: ProviderSnapshot?,
        currencyCode: String,
        synchronizedAt: Date
    ) -> [PlatformBalanceCostAnchor] {
        var anchors = officialCostAnchors(in: snapshot, currencyCode: currencyCode)
        guard
            let snapshot,
            snapshot.issue == nil,
            snapshot.capabilities.contains(.officialCostHistory),
            let coverage = snapshot.coverage,
            coverage.completeness == .complete
        else { return anchors }

        let interval = utcDayInterval(containing: synchronizedAt)
        let currentDayKey = PlatformBalanceAnchorKey(
            start: interval.start,
            end: interval.end,
            currencyCode: currencyCode
        )
        guard
            coverage.start <= interval.start,
            coverage.through >= interval.end,
            !anchors.contains(where: { anchorKey(for: $0) == currentDayKey })
        else { return anchors }

        anchors.append(
            PlatformBalanceCostAnchor(
                start: interval.start,
                end: interval.end,
                cost: try! Money(amount: 0, currencyCode: currencyCode)
            )
        )
        return anchors.sorted { $0.start < $1.start }
    }

    private func preservingMissingAnchorsAsZero(
        _ currentAnchors: [PlatformBalanceCostAnchor],
        from previousAnchors: [PlatformBalanceCostAnchor],
        coverage: ReportingCoverage?
    ) -> [PlatformBalanceCostAnchor] {
        guard let coverage else { return currentAnchors }
        var anchorsByKey = Dictionary(uniqueKeysWithValues: currentAnchors.map {
            (anchorKey(for: $0), $0)
        })

        for previous in previousAnchors {
            let key = anchorKey(for: previous)
            guard anchorsByKey[key] == nil else { continue }
            let isInsideCoverage = previous.start >= coverage.start && previous.end <= coverage.through
            anchorsByKey[key] = PlatformBalanceCostAnchor(
                start: previous.start,
                end: previous.end,
                cost: try! Money(
                    amount: isInsideCoverage ? 0 : previous.cost.amount,
                    currencyCode: previous.cost.currencyCode
                )
            )
        }

        return anchorsByKey.values.sorted { $0.start < $1.start }
    }

    private func anchorKey(for anchor: PlatformBalanceCostAnchor) -> PlatformBalanceAnchorKey {
        PlatformBalanceAnchorKey(
            start: anchor.start,
            end: anchor.end,
            currencyCode: anchor.cost.currencyCode
        )
    }

    private func utcDayInterval(containing date: Date) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: date)
        return DateInterval(
            start: start,
            end: calendar.date(byAdding: .day, value: 1, to: start)!
        )
    }

    private func persistPlatformBalances() {
        platformBalanceStore.save(platformBalanceCheckpoints)
    }

    private func officialUSDCosts(in snapshot: ProviderSnapshot) -> [Money] {
        snapshot.buckets.compactMap(officialUSDCost(in:))
    }

    private func officialUSDCost(in bucket: PeriodBucket) -> Money? {
        guard
            let cost = bucket.cost,
            cost.provenance == .official,
            cost.value.currencyCode == "USD"
        else { return nil }
        return cost.value
    }

    private func utcStartOfDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: date)
    }
}
