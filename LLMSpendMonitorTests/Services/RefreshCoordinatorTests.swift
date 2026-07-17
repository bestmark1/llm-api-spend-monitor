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

    func testTimerRespectsCadenceAndSkipsValidationOnlyProvider() async throws {
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

        _ = await coordinator.refresh(trigger: .credentialValidation, targets: [gemini])
        let validatedGeminiCallCount = await geminiProbe.callCount
        XCTAssertEqual(validatedGeminiCallCount, 1)
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
