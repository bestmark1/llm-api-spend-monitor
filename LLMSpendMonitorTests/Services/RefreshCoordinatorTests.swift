import XCTest
@testable import LLMSpendMonitor

final class RefreshCoordinatorTests: XCTestCase {
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
