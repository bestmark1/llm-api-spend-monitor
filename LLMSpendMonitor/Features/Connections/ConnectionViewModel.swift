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
    private let endpointStore: any ProviderEndpointStoring
    private let credentialDidChange: (ProviderID) -> Void

    @Published var draftSecret = ""
    @Published var draftEndpoint = ""
    @Published private(set) var connectionStatus: ConnectionStatus
    @Published private(set) var resultMessage: String?
    @Published private(set) var generation: UInt64 = 0

    var canSave: Bool {
        !draftSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!requiresAPIEndpoint || (try? QwenAPIEndpoint(draftEndpoint)) != nil)
    }

    var requiresAPIEndpoint: Bool { id == .qwen }

    var apiEndpointHelp: String? {
        guard requiresAPIEndpoint else { return nil }
        return "Paste the Base URL shown next to your key. Only official aliyuncs.com Model Studio endpoints are accepted."
    }

    var apiEndpointError: String? {
        guard requiresAPIEndpoint, !draftEndpoint.isEmpty else { return nil }
        guard (try? QwenAPIEndpoint(draftEndpoint)) == nil else { return nil }
        return "Enter an official Qwen OpenAI-compatible Base URL ending in /compatible-mode/v1."
    }

    var saveButtonTitle: String {
        connectionStatus == .connected ? "Replace" : "Save"
    }

    init(
        metadata: ProviderMetadata,
        accountID: String = CredentialIdentity.personalAccountID,
        credentialStore: CredentialStoring = KeychainStore(),
        endpointStore: any ProviderEndpointStoring = UserDefaultsProviderEndpointStore(),
        credentialDidChange: @escaping (ProviderID) -> Void = { _ in }
    ) {
        id = metadata.id
        self.metadata = metadata
        identity = CredentialIdentity(providerID: metadata.id, accountID: accountID)
        self.credentialStore = credentialStore
        self.endpointStore = endpointStore
        self.credentialDidChange = credentialDidChange
        if metadata.id == .qwen {
            draftEndpoint = endpointStore.loadEndpoint(for: metadata.id)
                ?? QwenAPIEndpoint.defaultValue
        }
        connectionStatus = Self.loadStatus(for: identity, from: credentialStore)
    }

    func saveOrReplace() {
        guard canSave else { return }

        do {
            if requiresAPIEndpoint {
                let endpoint = try QwenAPIEndpoint(draftEndpoint)
                endpointStore.saveEndpoint(endpoint.baseURL.absoluteString, for: id)
                draftEndpoint = endpoint.baseURL.absoluteString
            }
            try credentialStore.save(draftSecret, for: identity)
            draftSecret = ""
            connectionStatus = .connected
            generation &+= 1
            resultMessage = requiresAPIEndpoint
                ? "Credential saved. Qwen access will now be verified."
                : "Credential saved."
            credentialDidChange(id)
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
            credentialDidChange(id)
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
