import XCTest
@testable import LLMSpendMonitor

final class ProviderTargetFactoryTests: XCTestCase {
    func testOpenAITargetUsesKeychainCredentialAndUTCThirtyDayWindow() async throws {
        let store = TargetCredentialStore()
        try store.save("openai-admin-token", for: Self.openAIIdentity)
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
        try store.save("first-token", for: Self.openAIIdentity)
        let factory = ProviderTargetFactory(
            credentialStore: store,
            openAIProvider: ProviderClientRecorder()
        )
        let target = try XCTUnwrap(factory.makeTargets().first)

        let initiallyCurrent = await target.generationIsCurrent(target.generation)
        XCTAssertTrue(initiallyCurrent)

        try store.save("replacement-token", for: Self.openAIIdentity)
        let currentAfterReplacement = await target.generationIsCurrent(target.generation)
        XCTAssertFalse(currentAfterReplacement)

        try store.delete(for: Self.openAIIdentity)
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

    func testAnthropicTargetUsesAdminCredentialAndUTCThirtyDayWindow() async throws {
        let store = TargetCredentialStore()
        try store.save("anthropic-admin-token", for: Self.anthropicIdentity)
        let provider = ProviderClientRecorder(providerID: .anthropic)
        let now = Date(timeIntervalSince1970: 1_784_283_600)
        let factory = ProviderTargetFactory(
            credentialStore: store,
            openAIProvider: ProviderClientRecorder(),
            anthropicProvider: provider,
            now: { now }
        )

        let target = try XCTUnwrap(factory.makeTargets().first)
        _ = try await target.fetch()

        let call = await provider.lastCall
        XCTAssertEqual(target.providerID, .anthropic)
        XCTAssertEqual(target.minimumInterval, 15 * 60)
        XCTAssertEqual(call?.credential, "anthropic-admin-token")
        XCTAssertEqual(call?.request.purpose, .full)
        XCTAssertEqual(
            call?.request.reportingInterval,
            DateInterval(
                start: Date(timeIntervalSince1970: 1_781_740_800),
                end: Date(timeIntervalSince1970: 1_784_332_800)
            )
        )
    }

    func testDeepSeekTargetUsesStandardCredentialWithoutReportingWindow() async throws {
        let store = TargetCredentialStore()
        try store.save("deepseek-token", for: Self.deepSeekIdentity)
        let provider = ProviderClientRecorder(providerID: .deepSeek)
        let factory = ProviderTargetFactory(
            credentialStore: store,
            openAIProvider: ProviderClientRecorder(),
            anthropicProvider: ProviderClientRecorder(providerID: .anthropic),
            deepSeekProvider: provider
        )

        let target = try XCTUnwrap(factory.makeTargets().first)
        _ = try await target.fetch()

        let call = await provider.lastCall
        XCTAssertEqual(target.providerID, .deepSeek)
        XCTAssertEqual(target.minimumInterval, 5 * 60)
        XCTAssertEqual(call?.credential, "deepseek-token")
        XCTAssertEqual(call?.request.purpose, .full)
        XCTAssertNil(call?.request.reportingInterval)
    }

    func testCreatesTargetsForEveryConnectedProvider() throws {
        let store = TargetCredentialStore()
        try store.save("openai-admin-token", for: Self.openAIIdentity)
        try store.save("anthropic-admin-token", for: Self.anthropicIdentity)
        try store.save("deepseek-token", for: Self.deepSeekIdentity)
        let factory = ProviderTargetFactory(
            credentialStore: store,
            openAIProvider: ProviderClientRecorder(),
            anthropicProvider: ProviderClientRecorder(providerID: .anthropic),
            deepSeekProvider: ProviderClientRecorder(providerID: .deepSeek)
        )

        XCTAssertEqual(factory.makeTargets().map(\.providerID), [.openAI, .anthropic, .deepSeek])
    }

    private static let openAIIdentity = CredentialIdentity(providerID: .openAI)
    private static let anthropicIdentity = CredentialIdentity(providerID: .anthropic)
    private static let deepSeekIdentity = CredentialIdentity(providerID: .deepSeek)
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

    nonisolated let providerID: ProviderID
    nonisolated let capabilities: Set<ProviderCapability>
    private(set) var lastCall: Call?

    init(providerID: ProviderID = .openAI) {
        self.providerID = providerID
        capabilities = providerID == .deepSeek
            ? [.balance]
            : [.officialCostHistory, .tokenUsage, .modelBreakdown]
    }

    func fetch(
        _ request: ProviderFetchRequest,
        credential: String
    ) throws -> ProviderSnapshot {
        lastCall = Call(request: request, credential: credential)
        let interval = request.reportingInterval
        return try ProviderSnapshot(
            providerID: providerID,
            capabilities: capabilities,
            fetchedAt: interval?.end ?? Date(timeIntervalSince1970: 0),
            coverage: interval.map {
                ReportingCoverage(
                    start: $0.start,
                    through: $0.end,
                    completeness: .complete
                )
            },
            buckets: [],
            balances: [],
            issue: nil
        )
    }
}
