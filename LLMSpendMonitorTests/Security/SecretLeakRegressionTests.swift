import XCTest
@testable import LLMSpendMonitor

@MainActor
final class SecretLeakRegressionTests: XCTestCase {
    func testCanarySecretIsAbsentFromViewModelStateAndDescriptionsAfterSave() throws {
        let canary = "CANARY-U2-SECRET-DO-NOT-EXPOSE"
        let metadata = try XCTUnwrap(ProviderRegistry.metadata(for: .anthropic))
        let store = CanaryCredentialStore()
        let model = ConnectionViewModel(metadata: metadata, credentialStore: store)

        model.draftSecret = canary
        model.saveOrReplace()

        let exposedText = [
            model.draftSecret,
            model.connectionStatus.description,
            model.resultMessage ?? "",
            String(describing: model.identity),
            String(describing: KeychainStoreError(status: errSecParam))
        ].joined(separator: "\n")

        XCTAssertFalse(exposedText.contains(canary))
        XCTAssertEqual(store.savedSecret, canary)
    }
}

private final class CanaryCredentialStore: CredentialStoring {
    private(set) var savedSecret: String?

    func save(_ secret: String, for identity: CredentialIdentity) throws {
        savedSecret = secret
    }

    func read(for identity: CredentialIdentity) throws -> String {
        throw KeychainStoreError.itemNotFound
    }

    func delete(for identity: CredentialIdentity) throws {
        savedSecret = nil
    }
}
