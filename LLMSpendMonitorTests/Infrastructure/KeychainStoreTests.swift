import Security
import XCTest
@testable import LLMSpendMonitor

final class KeychainStoreTests: XCTestCase {
    private var store: KeychainStore!
    private var service: String!
    private let identities = ProviderID.allCases.map { CredentialIdentity(providerID: $0) }

    override func setUpWithError() throws {
        service = "com.bestmark.LLMSpendMonitorTests.\(UUID().uuidString)"
        store = KeychainStore(service: service)
    }

    override func tearDownWithError() throws {
        for identity in identities {
            try? store.delete(for: identity)
        }
        store = nil
        service = nil
    }

    func testSaveReadReplaceAndDelete() throws {
        let identity = CredentialIdentity(providerID: .openAI)

        do {
            try store.save("first-secret", for: identity)
            XCTAssertEqual(try store.read(for: identity), "first-secret")

            try store.save("replacement-secret", for: identity)
            XCTAssertEqual(try store.read(for: identity), "replacement-secret")

            try store.delete(for: identity)
            XCTAssertThrowsError(try store.read(for: identity)) { error in
                XCTAssertEqual(error as? KeychainStoreError, .itemNotFound)
            }
        } catch KeychainStoreError.unexpected(errSecMissingEntitlement) {
            throw XCTSkip("A signed application-identifier entitlement is required for live Data Protection Keychain tests.")
        }
    }

    func testReplaceMatchesProviderAndAccountOnly() throws {
        let openAI = CredentialIdentity(providerID: .openAI)
        let anthropic = CredentialIdentity(providerID: .anthropic)
        let secondOpenAIAccount = CredentialIdentity(providerID: .openAI, accountID: "secondary")

        do {
            try store.save("openai-primary", for: openAI)
            try store.save("anthropic-primary", for: anthropic)
            try store.save("openai-secondary", for: secondOpenAIAccount)
            try store.save("openai-primary-replaced", for: openAI)

            XCTAssertEqual(try store.read(for: openAI), "openai-primary-replaced")
            XCTAssertEqual(try store.read(for: anthropic), "anthropic-primary")
            XCTAssertEqual(try store.read(for: secondOpenAIAccount), "openai-secondary")
            try store.delete(for: secondOpenAIAccount)
        } catch KeychainStoreError.unexpected(errSecMissingEntitlement) {
            throw XCTSkip("A signed application-identifier entitlement is required for live Data Protection Keychain tests.")
        }
    }

    func testInjectedPerformerCoversExactCRUDAndProtectionAttributes() throws {
        let performer = MemorySecItemPerformer()
        let isolatedStore = KeychainStore(service: service, secItem: performer)
        let primary = CredentialIdentity(providerID: .openAI)
        let secondary = CredentialIdentity(providerID: .openAI, accountID: "secondary")

        try isolatedStore.save("primary", for: primary)
        try isolatedStore.save("secondary", for: secondary)
        try isolatedStore.save("primary-replaced", for: primary)

        XCTAssertEqual(try isolatedStore.read(for: primary), "primary-replaced")
        XCTAssertEqual(try isolatedStore.read(for: secondary), "secondary")
        XCTAssertEqual(performer.lastAddedAttributes?[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(performer.lastAddedAttributes?[kSecAttrSynchronizable] as? Bool, false)

        try isolatedStore.delete(for: primary)
        XCTAssertThrowsError(try isolatedStore.read(for: primary))
        XCTAssertEqual(try isolatedStore.read(for: secondary), "secondary")
    }

    func testQueriesOptIntoLocalDataProtectionKeychain() {
        let query = store.baseQuery(for: CredentialIdentity(providerID: .deepSeek))

        XCTAssertEqual(query[kSecUseDataProtectionKeychain] as? Bool, true)
        XCTAssertEqual(query[kSecAttrSynchronizable] as? Bool, false)
        XCTAssertEqual(query[kSecAttrService] as? String, service)
    }

    func testRecoverableStatusMapping() {
        XCTAssertEqual(KeychainStoreError(status: errSecItemNotFound), .itemNotFound)
        XCTAssertEqual(KeychainStoreError(status: errSecInteractionNotAllowed), .locked)
        XCTAssertEqual(KeychainStoreError(status: errSecUserCanceled), .cancelled)
        XCTAssertTrue(KeychainStoreError.locked.isRecoverable)
        XCTAssertTrue(KeychainStoreError.cancelled.isRecoverable)
    }
}

private final class MemorySecItemPerformer: SecItemPerforming {
    private var values: [String: Data] = [:]
    private(set) var lastAddedAttributes: [CFString: Any]?

    func add(_ attributes: CFDictionary) -> OSStatus {
        let dictionary = swiftDictionary(attributes)
        let key = itemKey(dictionary)
        guard values[key] == nil else { return errSecDuplicateItem }
        guard let data = dictionary[kSecValueData] as? Data else { return errSecParam }
        values[key] = data
        lastAddedAttributes = dictionary
        return errSecSuccess
    }

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus {
        let dictionary = swiftDictionary(query)
        guard let data = values[itemKey(dictionary)] else { return errSecItemNotFound }
        result.pointee = data as CFData
        return errSecSuccess
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        let queryDictionary = swiftDictionary(query)
        let key = itemKey(queryDictionary)
        guard values[key] != nil else { return errSecItemNotFound }
        let replacement = swiftDictionary(attributes)
        guard let data = replacement[kSecValueData] as? Data else { return errSecParam }
        values[key] = data
        return errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        let key = itemKey(swiftDictionary(query))
        guard values.removeValue(forKey: key) != nil else { return errSecItemNotFound }
        return errSecSuccess
    }

    private func swiftDictionary(_ dictionary: CFDictionary) -> [CFString: Any] {
        dictionary as NSDictionary as? [CFString: Any] ?? [:]
    }

    private func itemKey(_ dictionary: [CFString: Any]) -> String {
        "\(dictionary[kSecAttrService] as? String ?? "")|\(dictionary[kSecAttrAccount] as? String ?? "")"
    }
}
