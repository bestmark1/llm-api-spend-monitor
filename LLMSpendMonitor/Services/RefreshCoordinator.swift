import Foundation

actor RefreshCoordinator {
    private enum Outcome: Sendable {
        case success(ProviderSnapshot)
        case failure(ProviderID, ProviderIssue, retryAfter: TimeInterval?)
        case stale(ProviderID)

        var providerID: ProviderID {
            switch self {
            case let .success(snapshot): snapshot.providerID
            case let .failure(providerID, _, _), let .stale(providerID): providerID
            }
        }
    }

    private let cache: SnapshotCaching
    private let now: @Sendable () -> Date
    private let backoffPolicy: RefreshBackoffPolicy
    private var snapshots: [ProviderID: ProviderSnapshot] = [:]
    private var lastAttemptAt: [ProviderID: Date] = [:]
    private var consecutiveFailures: [ProviderID: Int] = [:]
    private var retryNotBefore: [ProviderID: Date] = [:]
    private var revisions: [ProviderID: UInt64] = [:]
    private var inFlight: Task<Void, Never>?

    init(
        cache: SnapshotCaching = SnapshotCache(),
        now: @escaping @Sendable () -> Date = Date.init,
        backoffPolicy: RefreshBackoffPolicy = RefreshBackoffPolicy()
    ) {
        self.cache = cache
        self.now = now
        self.backoffPolicy = backoffPolicy
    }

    func loadCachedSnapshots() async -> [ProviderID: ProviderSnapshot] {
        do {
            snapshots = try await cache.load()
        } catch {
            snapshots = [:]
        }
        return snapshots
    }

    func currentSnapshots() -> [ProviderID: ProviderSnapshot] {
        snapshots
    }

    func refresh(
        trigger: RefreshTrigger,
        targets: [ProviderRefreshTarget]
    ) async -> [ProviderID: ProviderSnapshot] {
        if let inFlight {
            await inFlight.value
            return snapshots
        }

        let eligibleTargets = targets.filter { isEligible($0, for: trigger) }
        guard !eligibleTargets.isEmpty else { return snapshots }

        let attemptRevisions = revisions
        let task = Task {
            await performRefresh(targets: eligibleTargets, attemptRevisions: attemptRevisions)
        }
        inFlight = task
        await task.value
        inFlight = nil
        return snapshots
    }

    func purge(_ providerID: ProviderID) async {
        revisions[providerID, default: 0] &+= 1
        snapshots.removeValue(forKey: providerID)
        lastAttemptAt.removeValue(forKey: providerID)
        consecutiveFailures.removeValue(forKey: providerID)
        retryNotBefore.removeValue(forKey: providerID)
        try? await cache.remove(providerID)
    }

    private func isEligible(
        _ target: ProviderRefreshTarget,
        for trigger: RefreshTrigger
    ) -> Bool {
        if let retryDate = retryNotBefore[target.providerID], now() < retryDate {
            return false
        }
        if !target.automaticRefreshEnabled {
            return trigger == .credentialValidation || trigger == .manual
        }
        if trigger == .credentialValidation || trigger == .manual {
            return true
        }
        guard let lastAttempt = lastAttemptAt[target.providerID] else {
            return true
        }
        return now().timeIntervalSince(lastAttempt) >= target.minimumInterval
    }

    private func performRefresh(
        targets: [ProviderRefreshTarget],
        attemptRevisions: [ProviderID: UInt64]
    ) async {
        let attemptedAt = now()
        let outcomes = await Self.fetchOutcomes(for: targets)

        for outcome in outcomes {
            // Recheck at publication, including failures buffered behind slower providers.
            // purge can run while credential validation awaits, so check the revision last.
            guard let target = targets.first(where: { $0.providerID == outcome.providerID }),
                  await target.generationIsCurrent(target.generation),
                  revisions[outcome.providerID, default: 0]
                    == attemptRevisions[outcome.providerID, default: 0]
            else { continue }
            switch outcome {
            case let .success(snapshot):
                lastAttemptAt[snapshot.providerID] = attemptedAt
                consecutiveFailures.removeValue(forKey: snapshot.providerID)
                retryNotBefore.removeValue(forKey: snapshot.providerID)
                snapshots[snapshot.providerID] = Self.mergingLocalMetrics(
                    into: snapshot,
                    previous: snapshots[snapshot.providerID]
                )
            case let .failure(providerID, issue, retryAfter):
                lastAttemptAt[providerID] = attemptedAt
                let failureCount = consecutiveFailures[providerID, default: 0] + 1
                consecutiveFailures[providerID] = failureCount
                let delay = backoffPolicy.delay(
                    consecutiveFailureCount: failureCount,
                    retryAfter: retryAfter
                )
                retryNotBefore[providerID] = attemptedAt.addingTimeInterval(delay)
                if let previous = snapshots[providerID] {
                    snapshots[providerID] = Self.retainingMetrics(from: previous, issue: issue)
                } else {
                    snapshots[providerID] = Self.diagnosticSnapshot(
                        providerID: providerID,
                        issue: issue,
                        attemptedAt: attemptedAt
                    )
                }
            case .stale:
                continue
            }

            try? await cache.save(snapshots)
        }
    }

    private static func fetchOutcomes(
        for targets: [ProviderRefreshTarget]
    ) async -> [Outcome] {
        await withTaskGroup(of: Outcome.self, returning: [Outcome].self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let snapshot = try await target.fetch()
                        guard snapshot.providerID == target.providerID else {
                            return .failure(target.providerID, .malformedResponse, retryAfter: nil)
                        }
                        guard await target.generationIsCurrent(target.generation) else {
                            return .stale(target.providerID)
                        }
                        return .success(snapshot)
                    } catch {
                        return .failure(
                            target.providerID,
                            issue(for: error),
                            retryAfter: retryAfter(for: error)
                        )
                    }
                }
            }

            var outcomes: [Outcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }
    }

    private static func issue(for error: Error) -> ProviderIssue {
        switch error {
        case ProviderClientError.invalidCredential:
            .authentication
        case ProviderClientError.insufficientPermissions:
            .insufficientPermissions
        case ProviderClientError.rateLimited:
            .rateLimited
        case ProviderClientError.offline:
            .offline
        case ProviderClientError.malformedResponse:
            .malformedResponse
        case ProviderClientError.unavailable:
            .providerUnavailable
        case KeychainStoreError.locked:
            .keychainLocked
        default:
            .providerUnavailable
        }
    }

    private static func retryAfter(for error: Error) -> TimeInterval? {
        guard
            case let .rateLimited(retryAfterSeconds) = error as? ProviderClientError
        else { return nil }
        return retryAfterSeconds
    }

    private static func retainingMetrics(
        from snapshot: ProviderSnapshot,
        issue: ProviderIssue
    ) -> ProviderSnapshot {
        (try? ProviderSnapshot(
            providerID: snapshot.providerID,
            capabilities: snapshot.capabilities,
            fetchedAt: snapshot.fetchedAt,
            coverage: snapshot.coverage,
            buckets: snapshot.buckets,
            balances: snapshot.balances,
            issue: issue
        )) ?? snapshot
    }

    private static func mergingLocalMetrics(
        into snapshot: ProviderSnapshot,
        previous: ProviderSnapshot?
    ) -> ProviderSnapshot {
        guard snapshot.providerID == .deepSeek else { return snapshot }

        let interval = thirtyDayUTCInterval(containing: snapshot.fetchedAt)
        var costsByDayAndCurrency: [BalanceCostKey: Decimal] = [:]

        if let previous {
            for bucket in previous.buckets {
                guard
                    bucket.start >= interval.start,
                    bucket.end <= interval.end,
                    let cost = bucket.cost,
                    cost.provenance == .estimated
                else { continue }
                costsByDayAndCurrency[
                    BalanceCostKey(day: bucket.start, currencyCode: cost.value.currencyCode),
                    default: 0
                ] += cost.value.amount
            }

            let previousBalances = previous.balances.reduce(into: [String: Decimal]()) {
                $0[$1.total.value.currencyCode] = $1.total.value.amount
            }
            let day = utcStartOfDay(snapshot.fetchedAt)
            for balance in snapshot.balances {
                let currencyCode = balance.total.value.currencyCode
                guard let oldAmount = previousBalances[currencyCode] else { continue }
                let decrease = oldAmount - balance.total.value.amount
                guard decrease > 0 else { continue }
                costsByDayAndCurrency[
                    BalanceCostKey(day: day, currencyCode: currencyCode),
                    default: 0
                ] += decrease
            }
        }

        let buckets = costsByDayAndCurrency.keys.sorted {
            $0.day == $1.day
                ? $0.currencyCode < $1.currencyCode
                : $0.day < $1.day
        }.compactMap { key -> PeriodBucket? in
            guard
                let amount = costsByDayAndCurrency[key],
                let money = try? Money(amount: amount, currencyCode: key.currencyCode)
            else { return nil }
            return PeriodBucket(
                start: key.day,
                end: key.day.addingTimeInterval(86_400),
                cost: MoneyMetric(value: money, provenance: .estimated)
            )
        }

        return (try? ProviderSnapshot(
            providerID: snapshot.providerID,
            capabilities: snapshot.capabilities.union([.estimatedCostHistory]),
            fetchedAt: snapshot.fetchedAt,
            coverage: ReportingCoverage(
                start: interval.start,
                through: interval.end,
                completeness: .complete
            ),
            buckets: buckets,
            balances: snapshot.balances,
            issue: snapshot.issue
        )) ?? snapshot
    }

    private static func thirtyDayUTCInterval(containing date: Date) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: date)
        return DateInterval(
            start: calendar.date(byAdding: .day, value: -29, to: today)!,
            end: calendar.date(byAdding: .day, value: 1, to: today)!
        )
    }

    private static func utcStartOfDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: date)
    }

    private static func diagnosticSnapshot(
        providerID: ProviderID,
        issue: ProviderIssue,
        attemptedAt: Date
    ) -> ProviderSnapshot? {
        guard let capabilities = ProviderRegistry.metadata(for: providerID)?.capabilities else {
            return nil
        }
        return try? ProviderSnapshot(
            providerID: providerID,
            capabilities: capabilities,
            fetchedAt: attemptedAt,
            coverage: nil,
            buckets: [],
            balances: [],
            issue: issue
        )
    }
}

private struct BalanceCostKey: Hashable {
    let day: Date
    let currencyCode: String
}
