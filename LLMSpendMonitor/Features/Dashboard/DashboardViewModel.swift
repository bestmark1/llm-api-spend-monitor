import Foundation

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

    private let dataSource: any DashboardDataRefreshing
    private let fixedTargets: [ProviderRefreshTarget]?
    private let targetFactory: ProviderTargetFactory
    private var hasStarted = false

    init(
        dataSource: any DashboardDataRefreshing = RefreshCoordinator(),
        targets: [ProviderRefreshTarget]? = nil,
        targetFactory: ProviderTargetFactory = ProviderTargetFactory()
    ) {
        self.dataSource = dataSource
        fixedTargets = targets
        self.targetFactory = targetFactory
    }

    var officialUSDTotal: Money {
        let total = snapshots.values.reduce(into: Decimal.zero) { result, snapshot in
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
