import XCTest
@testable import LLMSpendMonitor

@MainActor
final class ConnectionViewModelTests: XCTestCase {
    func testSaveReplaceAndDeleteIncrementGenerationAndClearDraft() throws {
        let store = InMemoryCredentialStore()
        let metadata = try XCTUnwrap(ProviderRegistry.metadata(for: .openAI))
        var changedProviders: [ProviderID] = []
        let model = ConnectionViewModel(
            metadata: metadata,
            credentialStore: store,
            credentialDidChange: { changedProviders.append($0) }
        )

        model.draftSecret = "CANARY-U2-SECRET"
        model.saveOrReplace()
        XCTAssertEqual(model.generation, 1)
        XCTAssertEqual(model.connectionStatus, .connected)
        XCTAssertEqual(model.draftSecret, "")

        model.draftSecret = "replacement"
        model.saveOrReplace()
        XCTAssertEqual(model.generation, 2)

        model.deleteCredential()
        XCTAssertEqual(model.generation, 3)
        XCTAssertEqual(model.connectionStatus, .notConnected)
        XCTAssertEqual(changedProviders, [.openAI, .openAI, .openAI])
    }

    func testQwenRequiresAndPersistsOnlyAnOfficialEndpoint() throws {
        let credentialStore = InMemoryCredentialStore()
        let endpointStore = InMemoryEndpointStore()
        let metadata = try XCTUnwrap(ProviderRegistry.metadata(for: .qwen))
        let model = ConnectionViewModel(
            metadata: metadata,
            credentialStore: credentialStore,
            endpointStore: endpointStore
        )

        XCTAssertEqual(model.draftEndpoint, QwenAPIEndpoint.defaultValue)
        model.draftSecret = "qwen-secret"
        model.draftEndpoint = "https://example.com/compatible-mode/v1"
        XCTAssertFalse(model.canSave)
        XCTAssertNotNil(model.apiEndpointError)

        model.draftEndpoint = "https://workspace.eu-central-1.maas.aliyuncs.com/compatible-mode/v1/"
        XCTAssertTrue(model.canSave)
        model.saveOrReplace()

        XCTAssertEqual(
            endpointStore.loadEndpoint(for: .qwen),
            "https://workspace.eu-central-1.maas.aliyuncs.com/compatible-mode/v1"
        )
        XCTAssertEqual(
            try credentialStore.read(for: CredentialIdentity(providerID: .qwen)),
            "qwen-secret"
        )
    }
}

private final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private var values: [CredentialIdentity: String] = [:]

    func save(_ secret: String, for identity: CredentialIdentity) throws {
        values[identity] = secret
    }

    func read(for identity: CredentialIdentity) throws -> String {
        guard let value = values[identity] else { throw KeychainStoreError.itemNotFound }
        return value
    }

    func delete(for identity: CredentialIdentity) throws {
        values.removeValue(forKey: identity)
    }
}

private final class InMemoryEndpointStore: ProviderEndpointStoring, @unchecked Sendable {
    private var values: [ProviderID: String] = [:]

    func loadEndpoint(for providerID: ProviderID) -> String? {
        values[providerID]
    }

    func saveEndpoint(_ endpoint: String, for providerID: ProviderID) {
        values[providerID] = endpoint
    }
}
