import XCTest
@testable import LLMSpendMonitor

final class ProviderTargetFactoryTests: XCTestCase {
    func testOpenAITargetUsesKeychainCredentialAndUTCThirtyDayWindow() async throws {
        let store = TargetCredentialStore()
        try store.save("openai-admin-token", for: Self.identity)
        let provider = ProviderClientRecorder()
        let now = Date(timeIntervalSince1970: 1_784_283_600)
        let factory = ProviderTargetFactory(
            credentialStore: store,
            openAIProvider: provider,
            now: { now }
        )

        let target = try XCTUnwrap(factory.makeTargets().first)
        _ = try await target.fetch()

        let call = await provider.lastCall
        XCTAssertEqual(target.providerID, .openAI)
        XCTAssertEqual(target.minimumInterval, 15 * 60)
        XCTAssertEqual(call?.credential, "openai-admin-token")
        XCTAssertEqual(call?.request.purpose, .full)
        XCTAssertEqual(
            call?.request.reportingInterval,
            DateInterval(
                start: Date(timeIntervalSince1970: 1_781_740_800),
                end: Date(timeIntervalSince1970: 1_784_332_800)
            )
        )
    }

    func testTargetBecomesStaleWhenCredentialIsReplacedOrDeleted() async throws {
        let store = TargetCredentialStore()
        try store.save("first-token", for: Self.identity)
        let factory = ProviderTargetFactory(
            credentialStore: store,
            openAIProvider: ProviderClientRecorder()
        )
        let target = try XCTUnwrap(factory.makeTargets().first)

        let initiallyCurrent = await target.generationIsCurrent(target.generation)
        XCTAssertTrue(initiallyCurrent)

        try store.save("replacement-token", for: Self.identity)
        let currentAfterReplacement = await target.generationIsCurrent(target.generation)
        XCTAssertFalse(currentAfterReplacement)

        try store.delete(for: Self.identity)
        let currentAfterDeletion = await target.generationIsCurrent(target.generation)
        XCTAssertFalse(currentAfterDeletion)
    }

    func testDisconnectedOpenAIDoesNotCreateRefreshTarget() {
        let factory = ProviderTargetFactory(
            credentialStore: TargetCredentialStore(),
            openAIProvider: ProviderClientRecorder()
        )

        XCTAssertTrue(factory.makeTargets().isEmpty)
    }

    private static let identity = CredentialIdentity(providerID: .openAI)
}

private final class TargetCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CredentialIdentity: String] = [:]

    func save(_ secret: String, for identity: CredentialIdentity) throws {
        lock.withLock { values[identity] = secret }
    }

    func read(for identity: CredentialIdentity) throws -> String {
        try lock.withLock {
            guard let value = values[identity] else { throw KeychainStoreError.itemNotFound }
            return value
        }
    }

    func delete(for identity: CredentialIdentity) throws {
        _ = lock.withLock { values.removeValue(forKey: identity) }
    }
}

private actor ProviderClientRecorder: ProviderClient {
    struct Call: Sendable {
        let request: ProviderFetchRequest
        let credential: String
    }

    nonisolated let providerID: ProviderID = .openAI
    nonisolated let capabilities: Set<ProviderCapability> = [
        .officialCostHistory,
        .tokenUsage,
        .modelBreakdown
    ]
    private(set) var lastCall: Call?

    func fetch(
        _ request: ProviderFetchRequest,
        credential: String
    ) throws -> ProviderSnapshot {
        lastCall = Call(request: request, credential: credential)
        let interval = request.reportingInterval!
        return try ProviderSnapshot(
            providerID: providerID,
            capabilities: capabilities,
            fetchedAt: interval.end,
            coverage: ReportingCoverage(
                start: interval.start,
                through: interval.end,
                completeness: .complete
            ),
            buckets: [],
            balances: [],
            issue: nil
        )
    }
}
