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
        let total = snapshots.keys.compactMap(snapshot(for:)).reduce(into: Decimal.zero) { result, snapshot in
            guard
                snapshot.issue == nil,
                snapshot.capabilities.contains(.officialCostHistory),
                snapshot.coverage?.completeness == .complete
            else { return }

            for bucket in snapshot.buckets {
                guard
                    let cost = bucket.cost,
                    cost.provenance == .official,
                    cost.value.currencyCode == "USD"
                else { continue }
                result += cost.value.amount
            }
        }
        return try! Money(amount: total, currencyCode: "USD")
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
}
