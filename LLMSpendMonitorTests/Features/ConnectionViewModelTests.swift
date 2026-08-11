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

    func testQwenRejectsTokenPlanKeyAndAllowsReplacingStoredPlanKey() throws {
        let credentialStore = InMemoryCredentialStore()
        let identity = CredentialIdentity(providerID: .qwen)
        try credentialStore.save("sk-sp-existing-plan-key", for: identity)
        let endpointStore = InMemoryEndpointStore()
        endpointStore.saveEndpoint(
            "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1",
            for: .qwen
        )
        let metadata = try XCTUnwrap(ProviderRegistry.metadata(for: .qwen))
        let model = ConnectionViewModel(
            metadata: metadata,
            credentialStore: credentialStore,
            endpointStore: endpointStore
        )

        XCTAssertEqual(model.connectionStatus, .error)
        XCTAssertTrue(model.canDeleteCredential)
        XCTAssertTrue(model.resultMessage?.contains("Token Plan") == true)
        XCTAssertTrue(model.apiEndpointError?.contains("Token Plan") == true)

        model.draftSecret = " sk-sp-replacement-plan-key "
        XCTAssertFalse(model.canSave)
        XCTAssertTrue(model.apiKeyError?.contains("pay-as-you-go") == true)
        model.saveOrReplace()
        XCTAssertEqual(try credentialStore.read(for: identity), "sk-sp-existing-plan-key")

        model.draftSecret = " sk-ws-pay-as-you-go-key "
        XCTAssertFalse(model.canSave)
        model.draftEndpoint = QwenAPIEndpoint.defaultValue
        XCTAssertTrue(model.canSave)
        model.saveOrReplace()

        XCTAssertEqual(model.connectionStatus, .connected)
        XCTAssertEqual(model.apiKeyError, nil)
        XCTAssertEqual(try credentialStore.read(for: identity), "sk-ws-pay-as-you-go-key")
    }

    func testQwenBillingCredentialsAreStoredSeparatelyAndCanBeDeleted() throws {
        let credentialStore = InMemoryCredentialStore()
        let metadata = try XCTUnwrap(ProviderRegistry.metadata(for: .qwen))
        var changedProviders: [ProviderID] = []
        let model = ConnectionViewModel(
            metadata: metadata,
            credentialStore: credentialStore,
            endpointStore: InMemoryEndpointStore(),
            credentialDidChange: { changedProviders.append($0) }
        )

        XCTAssertEqual(model.billingConnectionStatus, .notConnected)
        model.draftBillingAccessKeyID = " billing-id "
        model.draftBillingAccessKeySecret = " billing-secret "
        model.draftBillingProductCode = " model-studio-code "
        XCTAssertTrue(model.canSaveBilling)

        model.saveOrReplaceBillingCredentials()

        XCTAssertEqual(model.billingConnectionStatus, .connected)
        XCTAssertEqual(try credentialStore.read(for: QwenBillingCredentialIdentities.accessKeyID), "billing-id")
        XCTAssertEqual(try credentialStore.read(for: QwenBillingCredentialIdentities.accessKeySecret), "billing-secret")
        XCTAssertEqual(try credentialStore.read(for: QwenBillingCredentialIdentities.productCode), "model-studio-code")
        XCTAssertEqual(model.draftBillingAccessKeyID, "")
        XCTAssertEqual(model.draftBillingAccessKeySecret, "")
        XCTAssertEqual(model.draftBillingProductCode, "")

        model.deleteBillingCredentials()

        XCTAssertEqual(model.billingConnectionStatus, .notConnected)
        XCTAssertThrowsError(try credentialStore.read(for: QwenBillingCredentialIdentities.accessKeySecret))
        XCTAssertEqual(changedProviders, [.qwen, .qwen])
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
