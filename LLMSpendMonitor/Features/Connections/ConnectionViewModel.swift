import Foundation

@MainActor
final class ConnectionViewModel: ObservableObject, Identifiable {
    private static let qwenTokenPlanMessage = "Token Plan keys aren't supported. Use a pay-as-you-go Model Studio API key (sk-… or sk-ws-…)."

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
    @Published var draftBillingAccessKeyID = ""
    @Published var draftBillingAccessKeySecret = ""
    @Published var draftBillingProductCode = ""
    @Published private(set) var connectionStatus: ConnectionStatus
    @Published private(set) var billingConnectionStatus: ConnectionStatus = .notConnected
    @Published private(set) var usageConnectionStatus: ConnectionStatus = .notConnected
    @Published private(set) var resultMessage: String?
    @Published private(set) var billingResultMessage: String?
    @Published private(set) var usageResultMessage: String?
    @Published private(set) var generation: UInt64 = 0

    var canSave: Bool {
        !draftSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && apiKeyError == nil
            && (!requiresAPIEndpoint || (try? QwenAPIEndpoint(draftEndpoint)) != nil)
    }

    var requiresAPIEndpoint: Bool { id == .qwen }
    var supportsBillingCredentials: Bool { id == .qwen }
    var supportsUsageCredentials: Bool { id == .gemini }
    var canDeleteCredential: Bool { connectionStatus != .notConnected }
    var apiKeyPlaceholder: String { id == .qwen ? "Pay-as-you-go API key" : "API key" }

    var apiKeyError: String? {
        guard id == .qwen, QwenAPIKey.isTokenPlan(draftSecret) else { return nil }
        return Self.qwenTokenPlanMessage
    }

    var canSaveBilling: Bool {
        guard supportsBillingCredentials else { return false }
        return !draftBillingAccessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftBillingAccessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftBillingProductCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var apiEndpointHelp: String? {
        guard requiresAPIEndpoint else { return nil }
        return "Paste the API Host for your pay-as-you-go key. Token Plan endpoints are not supported."
    }

    var apiEndpointError: String? {
        guard requiresAPIEndpoint, !draftEndpoint.isEmpty else { return nil }
        guard (try? QwenAPIEndpoint(draftEndpoint)) == nil else { return nil }
        if URLComponents(string: draftEndpoint)?.host?.lowercased().hasPrefix("token-plan.") == true {
            return "Token Plan endpoints aren't supported. Use the API Host for a pay-as-you-go key."
        }
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
            billingConnectionStatus = Self.loadBundleStatus(
                identities: QwenBillingCredentialIdentities.all,
                from: credentialStore
            )
        }
        if metadata.id == .gemini {
            usageConnectionStatus = Self.loadBundleStatus(
                identities: GeminiMonitoringCredentialIdentities.all,
                from: credentialStore
            )
        }
        connectionStatus = Self.loadStatus(for: identity, from: credentialStore)
        if metadata.id == .qwen,
           let storedCredential = try? credentialStore.read(for: identity),
           QwenAPIKey.isTokenPlan(storedCredential) {
            connectionStatus = .error
            resultMessage = Self.qwenTokenPlanMessage
        }
    }

    func saveOrReplace() {
        guard canSave else { return }

        do {
            let normalizedSecret = draftSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            if requiresAPIEndpoint {
                let endpoint = try QwenAPIEndpoint(draftEndpoint)
                endpointStore.saveEndpoint(endpoint.baseURL.absoluteString, for: id)
                draftEndpoint = endpoint.baseURL.absoluteString
            }
            try credentialStore.save(normalizedSecret, for: identity)
            draftSecret = ""
            connectionStatus = .connected
            generation &+= 1
            resultMessage = requiresAPIEndpoint
                ? "Pay-as-you-go credential saved. Qwen access and billing will now be verified."
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

    func saveOrReplaceBillingCredentials() {
        guard canSaveBilling else { return }

        do {
            try credentialStore.save(
                draftBillingAccessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines),
                for: QwenBillingCredentialIdentities.accessKeySecret
            )
            try credentialStore.save(
                draftBillingAccessKeyID.trimmingCharacters(in: .whitespacesAndNewlines),
                for: QwenBillingCredentialIdentities.accessKeyID
            )
            try credentialStore.save(
                draftBillingProductCode.trimmingCharacters(in: .whitespacesAndNewlines),
                for: QwenBillingCredentialIdentities.productCode
            )
            draftBillingAccessKeyID = ""
            draftBillingAccessKeySecret = ""
            draftBillingProductCode = ""
            billingConnectionStatus = .connected
            generation &+= 1
            billingResultMessage = "Billing credentials saved. Alibaba Cloud balance and Qwen spend will now be refreshed."
            credentialDidChange(id)
        } catch {
            applyBilling(error)
        }
    }

    func deleteBillingCredentials() {
        do {
            for identity in QwenBillingCredentialIdentities.all {
                try credentialStore.delete(for: identity)
            }
            draftBillingAccessKeyID = ""
            draftBillingAccessKeySecret = ""
            draftBillingProductCode = ""
            billingConnectionStatus = .notConnected
            generation &+= 1
            billingResultMessage = "Billing credentials deleted."
            credentialDidChange(id)
        } catch {
            applyBilling(error)
        }
    }

    func saveGeminiUsageCredentials(_ data: Data) {
        guard supportsUsageCredentials, let json = String(data: data, encoding: .utf8) else {
            usageConnectionStatus = .error
            usageResultMessage = "Choose the JSON key downloaded for a Google Cloud service account."
            return
        }

        do {
            _ = try GeminiMonitoringCredentials(json: json)
            try credentialStore.save(
                json,
                for: GeminiMonitoringCredentialIdentities.serviceAccountJSON
            )
            usageConnectionStatus = .connected
            generation &+= 1
            usageResultMessage = "Google usage connected. Gemini tier, tokens, and models will now refresh automatically."
            credentialDidChange(id)
        } catch {
            usageConnectionStatus = .error
            usageResultMessage = "That file isn't a valid Google Cloud service account JSON key."
        }
    }

    func reportGeminiUsageImportFailure() {
        usageConnectionStatus = .error
        usageResultMessage = "The selected file couldn't be read."
    }

    func deleteGeminiUsageCredentials() {
        do {
            for identity in GeminiMonitoringCredentialIdentities.all {
                try credentialStore.delete(for: identity)
            }
            usageConnectionStatus = .notConnected
            generation &+= 1
            usageResultMessage = "Google usage connection deleted."
            credentialDidChange(id)
        } catch {
            if let keychainError = error as? KeychainStoreError, keychainError == .locked {
                usageConnectionStatus = .locked
                usageResultMessage = "Unlock your Mac and try again."
            } else {
                usageConnectionStatus = .error
                usageResultMessage = "Could not delete the Google usage connection."
            }
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

    private static func loadBundleStatus(
        identities: [CredentialIdentity],
        from store: CredentialStoring
    ) -> ConnectionStatus {
        do {
            let values = try identities.map { try store.read(for: $0) }
            return values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                ? .connected
                : .error
        } catch KeychainStoreError.itemNotFound {
            let presentCount = identities.reduce(into: 0) { result, identity in
                if (try? store.read(for: identity)) != nil { result += 1 }
            }
            return presentCount == 0 ? .notConnected : .error
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

    private func applyBilling(_ error: Error) {
        if let keychainError = error as? KeychainStoreError, keychainError == .locked {
            billingConnectionStatus = .locked
            billingResultMessage = "Unlock your Mac and try again."
        } else {
            billingConnectionStatus = .error
            billingResultMessage = "Could not update the billing credentials."
        }
    }
}
