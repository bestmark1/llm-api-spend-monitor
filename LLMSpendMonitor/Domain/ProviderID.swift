import Foundation

enum ProviderID: String, CaseIterable, Codable, Hashable, Sendable {
    case openAI = "openai"
    case anthropic
    case gemini
    case deepSeek = "deepseek"
    case kimi
    case qwen
    case xAI = "xai"
    case mistral
    case openRouter = "openrouter"
    case perplexity
}

struct CredentialIdentity: Hashable, Sendable {
    static let personalAccountID = "personal"

    let providerID: ProviderID
    let accountID: String

    init(providerID: ProviderID, accountID: String = personalAccountID) {
        self.providerID = providerID
        self.accountID = accountID
    }

    var keychainAccount: String {
        "\(providerID.rawValue):\(accountID)"
    }
}
