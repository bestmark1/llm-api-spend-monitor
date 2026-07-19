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

    func testSandboxAllowsRequiredOutboundNetworkAccessOnly() throws {
        let entitlementsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "LLMSpendMonitor/LLMSpendMonitor.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.network.client"] as? Bool, true)
        XCTAssertNil(entitlements["com.apple.security.network.server"])
    }
}

private final class CanaryCredentialStore: CredentialStoring, @unchecked Sendable {
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
