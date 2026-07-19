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

        let task = Task { await performRefresh(targets: eligibleTargets) }
        inFlight = task
        await task.value
        inFlight = nil
        return snapshots
    }

    func purge(_ providerID: ProviderID) async {
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
            return trigger == .credentialValidation
        }
        if trigger == .credentialValidation || trigger == .manual {
            return true
        }
        guard let lastAttempt = lastAttemptAt[target.providerID] else {
            return true
        }
        return now().timeIntervalSince(lastAttempt) >= target.minimumInterval
    }

    private func performRefresh(targets: [ProviderRefreshTarget]) async {
        let attemptedAt = now()
        let outcomes = await Self.fetchOutcomes(for: targets)

        for outcome in outcomes {
            switch outcome {
            case let .success(snapshot):
                lastAttemptAt[snapshot.providerID] = attemptedAt
                consecutiveFailures.removeValue(forKey: snapshot.providerID)
                retryNotBefore.removeValue(forKey: snapshot.providerID)
                snapshots[snapshot.providerID] = snapshot
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
