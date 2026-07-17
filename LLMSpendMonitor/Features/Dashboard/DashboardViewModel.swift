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
    @Published private(set) var isRefreshing = false
    @Published var selectedPeriod: DashboardPeriod = .today

    private let dataSource: any DashboardDataRefreshing
    private let fixedTargets: [ProviderRefreshTarget]?
    private let targetFactory: ProviderTargetFactory
    private let now: @Sendable () -> Date
    private var hasStarted = false

    init(
        dataSource: any DashboardDataRefreshing = RefreshCoordinator(),
        targets: [ProviderRefreshTarget]? = nil,
        targetFactory: ProviderTargetFactory = ProviderTargetFactory(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.dataSource = dataSource
        fixedTargets = targets
        self.targetFactory = targetFactory
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

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await loadCache()
        await refresh(trigger: .launch)
    }

    func loadCache() async {
        snapshots = await dataSource.loadCachedSnapshots()
    }

    func refresh(trigger: RefreshTrigger) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        snapshots = await dataSource.refresh(
            trigger: trigger,
            targets: fixedTargets ?? targetFactory.makeTargets()
        )
        isRefreshing = false
    }

    func credentialDidChange(_ providerID: ProviderID) async {
        snapshots.removeValue(forKey: providerID)
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
