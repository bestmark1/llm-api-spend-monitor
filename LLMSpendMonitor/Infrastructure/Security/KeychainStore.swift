import Foundation
import Security

protocol CredentialStoring: AnyObject, Sendable {
    func save(_ secret: String, for identity: CredentialIdentity) throws
    func read(for identity: CredentialIdentity) throws -> String
    func delete(for identity: CredentialIdentity) throws
}

enum KeychainStoreError: Error, Equatable, CustomStringConvertible {
    case itemNotFound
    case locked
    case cancelled
    case accessDenied
    case invalidData
    case unexpected(OSStatus)

    init(status: OSStatus) {
        switch status {
        case errSecItemNotFound:
            self = .itemNotFound
        case errSecInteractionNotAllowed:
            self = .locked
        case errSecUserCanceled:
            self = .cancelled
        case errSecAuthFailed:
            self = .accessDenied
        default:
            self = .unexpected(status)
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .itemNotFound, .locked, .cancelled:
            true
        case .accessDenied, .invalidData, .unexpected:
            false
        }
    }

    var description: String {
        switch self {
        case .itemNotFound:
            "Credential not found."
        case .locked:
            "Credentials are unavailable while the keychain is locked."
        case .cancelled:
            "Credential access was cancelled."
        case .accessDenied:
            "Credential access was denied."
        case .invalidData:
            "Credential data is invalid."
        case let .unexpected(status):
            "Keychain operation failed with status \(status)."
        }
    }
}

protocol SecItemPerforming: AnyObject {
    func add(_ attributes: CFDictionary) -> OSStatus
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

private final class SystemSecItemPerformer: SecItemPerforming {
    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus {
        SecItemCopyMatching(query, result)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

final class KeychainStore: CredentialStoring, @unchecked Sendable {
    static let defaultService = "com.bestmark.LLMSpendMonitor.credentials.v1"

    private let service: String
    private let secItem: SecItemPerforming

    init(
        service: String = KeychainStore.defaultService,
        secItem: SecItemPerforming = SystemSecItemPerformer()
    ) {
        self.service = service
        self.secItem = secItem
    }

    func save(_ secret: String, for identity: CredentialIdentity) throws {
        let secretData = Data(secret.utf8)
        let query = baseQuery(for: identity)
        let replacement: [CFString: Any] = [
            kSecValueData: secretData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = secItem.update(query as CFDictionary, attributes: replacement as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = query
            replacement.forEach { attributes[$0.key] = $0.value }
            let addStatus = secItem.add(attributes as CFDictionary)

            if addStatus == errSecDuplicateItem {
                try check(secItem.update(query as CFDictionary, attributes: replacement as CFDictionary))
            } else {
                try check(addStatus)
            }
        default:
            throw KeychainStoreError(status: updateStatus)
        }
    }

    func read(for identity: CredentialIdentity) throws -> String {
        var query = baseQuery(for: identity)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        try check(secItem.copyMatching(query as CFDictionary, result: &result))

        guard
            let data = result as? Data,
            let secret = String(data: data, encoding: .utf8)
        else {
            throw KeychainStoreError.invalidData
        }
        return secret
    }

    func delete(for identity: CredentialIdentity) throws {
        let status = secItem.delete(baseQuery(for: identity) as CFDictionary)
        guard status != errSecItemNotFound else { return }
        try check(status)
    }

    func baseQuery(for identity: CredentialIdentity) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: identity.keychainAccount,
            kSecUseDataProtectionKeychain: true,
            kSecAttrSynchronizable: false
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw KeychainStoreError(status: status)
        }
    }
}
