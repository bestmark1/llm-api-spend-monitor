import XCTest
@testable import LLMSpendMonitor

final class RefreshCoordinatorTests: XCTestCase {
    func testStaleFailureMustNotRestorePurgedProvider() async throws {
        let cache = InMemorySnapshotCache()
        let coordinator = RefreshCoordinator(cache: cache)
        let target = ProviderRefreshTarget(
            providerID: .openAI, generation: 1, minimumInterval: 0,
            automaticRefreshEnabled: true,
            fetch: { throw ProviderClientError.invalidCredential },
            generationIsCurrent: { _ in false }
        )
        await coordinator.purge(.openAI)
        let result = await coordinator.refresh(trigger: .manual, targets: [target])
        XCTAssertNil(result[.openAI], "An obsolete credential failure must not restore Action needed")
        let persisted = await cache.load()
        XCTAssertNil(persisted[.openAI], "An obsolete credential failure must not persist")
    }

    func testDeletionAfterFastProviderCompletesMustSurviveSlowProvider() async throws {
        for invalidatesCredential in [false, true] {
        let cache = InMemorySnapshotCache()
        let coordinator = RefreshCoordinator(cache: cache)
        let didCheck = RefreshTestLatch()
        let unblockSlow = RefreshTestLatch()
        let generation = RefreshTestGenerationFlag()
        let fastSnapshot = try makeSnapshot(providerID: .openAI, amount: "5.00")
        let slowSnapshot = try makeSnapshot(providerID: .anthropic, amount: "1.00")
        let fast = ProviderRefreshTarget(
            providerID: .openAI, generation: 1, minimumInterval: 0,
            automaticRefreshEnabled: true, fetch: { fastSnapshot },
            generationIsCurrent: { _ in
                let current = await generation.current
                await didCheck.release()
                return current
            })
        let slow = ProviderRefreshTarget(
            providerID: .anthropic, generation: 1, minimumInterval: 0,
            automaticRefreshEnabled: true,
            fetch: { await unblockSlow.wait(); return slowSnapshot },
            generationIsCurrent: { _ in true })
        let running = Task { await coordinator.refresh(trigger: .manual, targets: [fast, slow]) }
        await didCheck.wait()
        if invalidatesCredential { await generation.invalidate() }
        await coordinator.purge(.openAI)
        await unblockSlow.release()
        let snapshots = await running.value
        XCTAssertNil(snapshots[.openAI], "Deleted provider restored from buffered successful response")
        let persisted = await cache.load()
        XCTAssertNil(persisted[.openAI], "Deleted provider persisted again")
        }
    }

    func testSimultaneousTriggersCoalesceIntoOneFetch() async throws {
        let cache = InMemorySnapshotCache()
        let coordinator = RefreshCoordinator(cache: cache, now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let probe = FetchProbe(result: .success(try makeSnapshot(providerID: .openAI, amount: "1.00")), delayNanoseconds: 100_000_000)
        let target = makeTarget(providerID: .openAI, probe: probe)

        async let first = coordinator.refresh(trigger: .manual, targets: [target])
        async let second = coordinator.refresh(trigger: .panelOpen, targets: [target])
        _ = await (first, second)

        let callCount = await probe.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testProviderFailureKeepsLastGoodSnapshotAndDoesNotBlockOthers() async throws {
        let previous = try makeSnapshot(providerID: .openAI, amount: "1.00")
        let cache = InMemorySnapshotCache(initial: [.openAI: previous])
        let coordinator = RefreshCoordinator(cache: cache, now: { Date(timeIntervalSince1970: 2_000_000_000) })
        _ = await coordinator.loadCachedSnapshots()

        let failingProbe = FetchProbe(result: .failure(ProviderClientError.unavailable))
        let successfulSnapshot = try makeSnapshot(providerID: .anthropic, amount: "2.00")
        let successfulProbe = FetchProbe(result: .success(successfulSnapshot))

        let snapshots = await coordinator.refresh(
            trigger: .manual,
            targets: [
                makeTarget(providerID: .openAI, probe: failingProbe),
                makeTarget(providerID: .anthropic, probe: successfulProbe)
            ]
        )

        XCTAssertEqual(snapshots[.openAI]?.buckets, previous.buckets)
        XCTAssertEqual(snapshots[.openAI]?.issue, .providerUnavailable)
        XCTAssertEqual(snapshots[.anthropic], successfulSnapshot)
    }

    func testInitialProviderFailureCreatesDiagnosticSnapshot() async {
        let attemptedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let coordinator = RefreshCoordinator(
            cache: InMemorySnapshotCache(),
            now: { attemptedAt }
        )
        let probe = FetchProbe(result: .failure(ProviderClientError.invalidCredential))

        let snapshots = await coordinator.refresh(
            trigger: .credentialValidation,
            targets: [makeTarget(providerID: .openAI, probe: probe)]
        )

        XCTAssertEqual(snapshots[.openAI]?.issue, .authentication)
        XCTAssertEqual(snapshots[.openAI]?.fetchedAt, attemptedAt)
        XCTAssertEqual(
            snapshots[.openAI]?.capabilities,
            [.officialCostHistory, .tokenUsage, .modelBreakdown]
        )
        XCTAssertTrue(snapshots[.openAI]?.buckets.isEmpty == true)
    }

    func testDeepSeekFortyDayGapMustNotBecomeTodaysSpend() async throws {
        let firstDate = Date(timeIntervalSince1970: 1_784_332_800)
        let secondDate = firstDate.addingTimeInterval(40 * 86_400)
        let coordinator = RefreshCoordinator(cache: InMemorySnapshotCache(), now: { secondDate })
        let probe = SequencedFetchProbe(results: [
            .success(try makeBalanceSnapshot(providerID: .deepSeek, amount: "10.00", fetchedAt: firstDate)),
            .success(try makeBalanceSnapshot(providerID: .deepSeek, amount: "5.00", fetchedAt: secondDate))
        ])
        let target = makeTarget(providerID: .deepSeek, fetch: { try await probe.fetch() })
        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        let result = await coordinator.refresh(trigger: .manual, targets: [target])
        let snapshot = try XCTUnwrap(result[.deepSeek])
        XCTAssertTrue(snapshot.buckets.isEmpty, "A 40-day unobserved delta is not a known daily expense")
        XCTAssertNotEqual(snapshot.coverage?.completeness, .complete,
                          "Two samples cannot establish complete 30-day spend coverage")
    }

    func testDeepSeekBalanceDecreaseCreatesEstimatedDailySpendAndPersistsIt() async throws {
        let firstDate = Date(timeIntervalSince1970: 1_784_332_800)
        let secondDate = firstDate.addingTimeInterval(86_400)
        let cache = InMemorySnapshotCache()
        let coordinator = RefreshCoordinator(cache: cache, now: { secondDate })
        let probe = SequencedFetchProbe(results: [
            .success(try makeBalanceSnapshot(providerID: .deepSeek, amount: "10.00", fetchedAt: firstDate)),
            .success(try makeBalanceSnapshot(providerID: .deepSeek, amount: "8.30", fetchedAt: secondDate))
        ])
        let target = makeTarget(providerID: .deepSeek, fetch: { try await probe.fetch() })

        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        let snapshots = await coordinator.refresh(trigger: .manual, targets: [target])

        let deepSeek = try XCTUnwrap(snapshots[.deepSeek])
        XCTAssertEqual(deepSeek.capabilities, [.balance, .estimatedCostHistory])
        XCTAssertEqual(deepSeek.buckets.count, 1)
        XCTAssertEqual(deepSeek.buckets.first?.cost?.value.amount, Decimal(string: "1.70"))
        XCTAssertEqual(deepSeek.buckets.first?.cost?.provenance, .estimated)
        XCTAssertEqual(deepSeek.buckets.first?.start, firstDate)
        XCTAssertEqual(deepSeek.buckets.first?.end, secondDate)
        XCTAssertEqual(deepSeek.coverage?.completeness, .partial)

        let persisted = await cache.load()
        XCTAssertEqual(persisted[.deepSeek], deepSeek)
    }

    func testRepeatedBalanceTimestampDoesNotDuplicateEstimatedSpend() async throws {
        let day = Date(timeIntervalSince1970: 1_784_332_800)
        let coordinator = RefreshCoordinator(cache: InMemorySnapshotCache())
        let first = try makeBalanceSnapshot(providerID: .deepSeek, amount: "10", fetchedAt: day)
        let second = try makeBalanceSnapshot(providerID: .deepSeek, amount: "9", fetchedAt: day.addingTimeInterval(3600))
        let probe = SequencedFetchProbe(results: [.success(first), .success(second), .success(second)])
        let target = makeTarget(providerID: .deepSeek, fetch: { try await probe.fetch() })
        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        let initial = await coordinator.refresh(trigger: .manual, targets: [target])
        let repeated = await coordinator.refresh(trigger: .manual, targets: [target])
        XCTAssertEqual(repeated, initial)
        let snapshot = try XCTUnwrap(repeated[.deepSeek])
        let restored = try JSONDecoder().decode(ProviderSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.buckets.first?.start, day)
        XCTAssertEqual(restored.buckets.first?.end, day.addingTimeInterval(3600))
        XCTAssertEqual(restored.buckets.first?.cost?.value.amount, 1)
    }

    func testDeepSeekTopUpDoesNotCreateSpendOrDiscardEarlierEstimate() async throws {
        let firstDate = Date(timeIntervalSince1970: 1_784_332_800)
        let secondDate = firstDate.addingTimeInterval(86_400)
        let thirdDate = secondDate.addingTimeInterval(86_400)
        let coordinator = RefreshCoordinator(
            cache: InMemorySnapshotCache(),
            now: { thirdDate }
        )
        let probe = SequencedFetchProbe(results: [
            .success(try makeBalanceSnapshot(providerID: .deepSeek, amount: "10.00", fetchedAt: firstDate)),
            .success(try makeBalanceSnapshot(providerID: .deepSeek, amount: "8.30", fetchedAt: secondDate)),
            .success(try makeBalanceSnapshot(providerID: .deepSeek, amount: "12.00", fetchedAt: thirdDate))
        ])
        let target = makeTarget(providerID: .deepSeek, fetch: { try await probe.fetch() })

        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        let snapshots = await coordinator.refresh(trigger: .manual, targets: [target])

        let deepSeek = try XCTUnwrap(snapshots[.deepSeek])
        XCTAssertEqual(deepSeek.buckets.count, 1)
        XCTAssertEqual(deepSeek.buckets.first?.cost?.value.amount, Decimal(string: "1.70"))
        XCTAssertEqual(deepSeek.balances.first?.total.value.amount, Decimal(string: "12.00"))
    }

    func testTimerSkipsButManualRefreshesValidationOnlyProvider() async throws {
        let cache = InMemorySnapshotCache()
        let coordinator = RefreshCoordinator(cache: cache, now: { Date(timeIntervalSince1970: 2_000_000_000) })
        let openAIProbe = FetchProbe(result: .success(try makeSnapshot(providerID: .openAI, amount: "1.00")))
        let geminiProbe = FetchProbe(result: .success(try makeConnectionOnlySnapshot(providerID: .gemini)))
        let openAI = makeTarget(providerID: .openAI, minimumInterval: 900, probe: openAIProbe)
        let gemini = makeTarget(providerID: .gemini, automaticRefreshEnabled: false, probe: geminiProbe)

        _ = await coordinator.refresh(trigger: .timer, targets: [openAI, gemini])
        _ = await coordinator.refresh(trigger: .timer, targets: [openAI, gemini])

        let openAICallCount = await openAIProbe.callCount
        let automaticGeminiCallCount = await geminiProbe.callCount
        XCTAssertEqual(openAICallCount, 1)
        XCTAssertEqual(automaticGeminiCallCount, 0)

        _ = await coordinator.refresh(trigger: .manual, targets: [gemini])
        let manualGeminiCallCount = await geminiProbe.callCount
        XCTAssertEqual(manualGeminiCallCount, 1)

        _ = await coordinator.refresh(trigger: .credentialValidation, targets: [gemini])
        let validatedGeminiCallCount = await geminiProbe.callCount
        XCTAssertEqual(validatedGeminiCallCount, 2)
    }

    func testStaleCredentialGenerationCannotRestorePurgedSnapshot() async throws {
        let previous = try makeSnapshot(providerID: .openAI, amount: "1.00")
        let cache = InMemorySnapshotCache(initial: [.openAI: previous])
        let coordinator = RefreshCoordinator(cache: cache, now: { Date(timeIntervalSince1970: 2_000_000_000) })
        _ = await coordinator.loadCachedSnapshots()
        await coordinator.purge(.openAI)

        let probe = FetchProbe(result: .success(try makeSnapshot(providerID: .openAI, amount: "9.00")))
        let staleTarget = ProviderRefreshTarget(
            providerID: .openAI,
            generation: 1,
            minimumInterval: 0,
            automaticRefreshEnabled: true,
            fetch: { try await probe.fetch() },
            generationIsCurrent: { _ in false }
        )

        let snapshots = await coordinator.refresh(trigger: .manual, targets: [staleTarget])

        XCTAssertNil(snapshots[.openAI])
        let cached = await cache.load()
        XCTAssertNil(cached[.openAI])
    }

    func testRetryAfterBlocksEveryTriggerUntilProviderCooldownExpires() async throws {
        let clock = LockedTestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let coordinator = RefreshCoordinator(
            cache: InMemorySnapshotCache(),
            now: { clock.now },
            backoffPolicy: RefreshBackoffPolicy(baseDelay: 10, maximumDelay: 300, jitter: { 0.5 })
        )
        let probe = SequencedFetchProbe(results: [
            .failure(ProviderClientError.rateLimited(retryAfterSeconds: 120)),
            .success(try makeSnapshot(providerID: .openAI, amount: "2.00"))
        ])
        let target = makeTarget(providerID: .openAI, fetch: { try await probe.fetch() })

        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        clock.advance(by: 119)
        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        let callsBeforeRetryAfter = await probe.callCount
        XCTAssertEqual(callsBeforeRetryAfter, 1)

        clock.advance(by: 1)
        _ = await coordinator.refresh(trigger: .panelOpen, targets: [target])
        let callsAfterRetryAfter = await probe.callCount
        XCTAssertEqual(callsAfterRetryAfter, 2)
    }

    func testFailuresUseDeterministicExponentialBackoff() async throws {
        let clock = LockedTestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let coordinator = RefreshCoordinator(
            cache: InMemorySnapshotCache(),
            now: { clock.now },
            backoffPolicy: RefreshBackoffPolicy(baseDelay: 10, maximumDelay: 60, jitter: { 0.5 })
        )
        let probe = SequencedFetchProbe(results: [
            .failure(ProviderClientError.unavailable),
            .failure(ProviderClientError.unavailable),
            .failure(ProviderClientError.unavailable)
        ])
        let target = makeTarget(providerID: .anthropic, fetch: { try await probe.fetch() })

        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        clock.advance(by: 9)
        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        let callsDuringFirstBackoff = await probe.callCount
        XCTAssertEqual(callsDuringFirstBackoff, 1)

        clock.advance(by: 1)
        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        clock.advance(by: 19)
        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        let callsDuringSecondBackoff = await probe.callCount
        XCTAssertEqual(callsDuringSecondBackoff, 2)

        clock.advance(by: 1)
        _ = await coordinator.refresh(trigger: .manual, targets: [target])
        let callsAfterSecondBackoff = await probe.callCount
        XCTAssertEqual(callsAfterSecondBackoff, 3)
    }

    private func makeTarget(
        providerID: ProviderID,
        generation: UInt64 = 0,
        minimumInterval: TimeInterval = 300,
        automaticRefreshEnabled: Bool = true,
        probe: FetchProbe
    ) -> ProviderRefreshTarget {
        ProviderRefreshTarget(
            providerID: providerID,
            generation: generation,
            minimumInterval: minimumInterval,
            automaticRefreshEnabled: automaticRefreshEnabled,
            fetch: { try await probe.fetch() },
            generationIsCurrent: { _ in true }
        )
    }

    private func makeTarget(
        providerID: ProviderID,
        fetch: @escaping @Sendable () async throws -> ProviderSnapshot
    ) -> ProviderRefreshTarget {
        ProviderRefreshTarget(
            providerID: providerID,
            generation: 0,
            minimumInterval: 0,
            automaticRefreshEnabled: true,
            fetch: fetch,
            generationIsCurrent: { _ in true }
        )
    }

    private func makeSnapshot(providerID: ProviderID, amount: String) throws -> ProviderSnapshot {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400)
        let cost = MoneyMetric(
            value: try Money(amount: Decimal(string: amount)!, currencyCode: "USD"),
            provenance: .official
        )
        return try ProviderSnapshot(
            providerID: providerID,
            capabilities: [.officialCostHistory],
            fetchedAt: end,
            coverage: ReportingCoverage(start: start, through: end, completeness: .complete),
            buckets: [PeriodBucket(start: start, end: end, cost: cost)],
            balances: [],
            issue: nil
        )
    }

    private func makeConnectionOnlySnapshot(providerID: ProviderID) throws -> ProviderSnapshot {
        try ProviderSnapshot(
            providerID: providerID,
            capabilities: [.credentialValidation],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            coverage: nil,
            buckets: [],
            balances: [],
            issue: nil
        )
    }

    private func makeBalanceSnapshot(
        providerID: ProviderID,
        amount: String,
        fetchedAt: Date
    ) throws -> ProviderSnapshot {
        let balance = ProviderBalance(
            total: MoneyMetric(
                value: try Money(amount: Decimal(string: amount)!, currencyCode: "USD"),
                provenance: .official
            ),
            granted: nil,
            toppedUp: nil
        )
        return try ProviderSnapshot(
            providerID: providerID,
            capabilities: [.balance],
            fetchedAt: fetchedAt,
            coverage: nil,
            buckets: [],
            balances: [balance],
            issue: nil
        )
    }
}

private actor SequencedFetchProbe {
    private(set) var callCount = 0
    private var results: [Result<ProviderSnapshot, Error>]

    init(results: [Result<ProviderSnapshot, Error>]) {
        self.results = results
    }

    func fetch() throws -> ProviderSnapshot {
        callCount += 1
        return try results.removeFirst().get()
    }
}

private final class LockedTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var now: Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(interval) }
    }
}

private actor FetchProbe {
    private(set) var callCount = 0
    private let result: Result<ProviderSnapshot, Error>
    private let delayNanoseconds: UInt64

    init(result: Result<ProviderSnapshot, Error>, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func fetch() async throws -> ProviderSnapshot {
        callCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }
}

private actor InMemorySnapshotCache: SnapshotCaching {
    private var snapshots: [ProviderID: ProviderSnapshot]

    init(initial: [ProviderID: ProviderSnapshot] = [:]) {
        snapshots = initial
    }

    func load() -> [ProviderID: ProviderSnapshot] {
        snapshots
    }

    func save(_ snapshots: [ProviderID: ProviderSnapshot]) {
        self.snapshots = snapshots
    }

    func remove(_ providerID: ProviderID) {
        snapshots.removeValue(forKey: providerID)
    }
}

private actor RefreshTestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
private actor RefreshTestGenerationFlag {
    private(set) var current = true
    func invalidate() { current = false }
}
