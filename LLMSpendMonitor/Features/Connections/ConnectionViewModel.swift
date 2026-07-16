import Foundation

@MainActor
final class ConnectionViewModel: ObservableObject, Identifiable {
    enum ConnectionStatus: Equatable, CustomStringConvertible {
        case notConnected
        case connected
        case locked
        case error

        var description: String {
            switch self {
            case .notConnected:
                "Not connected"
            case .connected:
                "Connected"
            case .locked:
                "Keychain locked"
            case .error:
                "Credential unavailable"
            }
        }
    }

    nonisolated let id: ProviderID
    let metadata: ProviderMetadata
    let identity: CredentialIdentity
    private let credentialStore: CredentialStoring

    @Published var draftSecret = ""
    @Published private(set) var connectionStatus: ConnectionStatus
    @Published private(set) var resultMessage: String?
    @Published private(set) var generation: UInt64 = 0

    var canSave: Bool {
        !draftSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var saveButtonTitle: String {
        connectionStatus == .connected ? "Replace" : "Save"
    }

    init(
        metadata: ProviderMetadata,
        accountID: String = CredentialIdentity.personalAccountID,
        credentialStore: CredentialStoring = KeychainStore()
    ) {
        id = metadata.id
        self.metadata = metadata
        identity = CredentialIdentity(providerID: metadata.id, accountID: accountID)
        self.credentialStore = credentialStore
        connectionStatus = Self.loadStatus(for: identity, from: credentialStore)
    }

    func saveOrReplace() {
        guard canSave else { return }

        do {
            try credentialStore.save(draftSecret, for: identity)
            draftSecret = ""
            connectionStatus = .connected
            generation &+= 1
            resultMessage = "Credential saved."
        } catch {
            apply(error)
        }
    }

    func deleteCredential() {
        do {
            try credentialStore.delete(for: identity)
            draftSecret = ""
            connectionStatus = .notConnected
            generation &+= 1
            resultMessage = "Credential deleted."
        } catch {
            apply(error)
        }
    }

    private static func loadStatus(
        for identity: CredentialIdentity,
        from store: CredentialStoring
    ) -> ConnectionStatus {
        do {
            _ = try store.read(for: identity)
            return .connected
        } catch KeychainStoreError.itemNotFound {
            return .notConnected
        } catch KeychainStoreError.locked {
            return .locked
        } catch {
            return .error
        }
    }

    private func apply(_ error: Error) {
        if let keychainError = error as? KeychainStoreError, keychainError == .locked {
            connectionStatus = .locked
            resultMessage = "Unlock your Mac and try again."
        } else {
            connectionStatus = .error
            resultMessage = "Could not update the credential."
        }
    }
}
