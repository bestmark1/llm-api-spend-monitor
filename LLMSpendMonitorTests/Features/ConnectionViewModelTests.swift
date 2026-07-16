import XCTest
@testable import LLMSpendMonitor

@MainActor
final class ConnectionViewModelTests: XCTestCase {
    func testSaveReplaceAndDeleteIncrementGenerationAndClearDraft() throws {
        let store = InMemoryCredentialStore()
        let metadata = try XCTUnwrap(ProviderRegistry.metadata(for: .openAI))
        let model = ConnectionViewModel(metadata: metadata, credentialStore: store)

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
    }
}

private final class InMemoryCredentialStore: CredentialStoring {
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
