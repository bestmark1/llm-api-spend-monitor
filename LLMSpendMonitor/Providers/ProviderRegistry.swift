import Foundation

struct ProviderMetadata: Identifiable, Equatable, Sendable {
    let id: ProviderID
    let displayName: String
    let systemImageName: String
    let credentialHelp: String
    let capabilities: Set<ProviderCapability>
    let externalLinks: [ExternalLink]
}

enum ProviderRegistry {
    static let all: [ProviderMetadata] = [
        ProviderMetadata(
            id: .openAI,
            displayName: "OpenAI",
            systemImageName: "circle.hexagongrid",
            credentialHelp: "Requires an Organization Admin API key for official usage and cost reports.",
            capabilities: [.officialCostHistory, .tokenUsage],
            externalLinks: [
                link(.usage, "https://platform.openai.com/usage"),
                link(.billing, "https://platform.openai.com/settings/organization/billing/overview"),
                link(.dashboard, "https://platform.openai.com/settings/organization/general"),
                link(.status, "https://status.openai.com")
            ]
        ),
        ProviderMetadata(
            id: .anthropic,
            displayName: "Anthropic",
            systemImageName: "sparkles",
            credentialHelp: "Requires a Console Admin API key for official usage and cost reports.",
            capabilities: [.officialCostHistory, .tokenUsage],
            externalLinks: [
                link(.usage, "https://console.anthropic.com/settings/usage"),
                link(.billing, "https://console.anthropic.com/settings/billing"),
                link(.dashboard, "https://console.anthropic.com"),
                link(.status, "https://status.anthropic.com")
            ]
        ),
        ProviderMetadata(
            id: .gemini,
            displayName: "Gemini",
            systemImageName: "diamond",
            credentialHelp: "A Gemini API key validates access. Basic keys do not expose official cost or balance data.",
            capabilities: [.credentialValidation],
            externalLinks: [
                link(.usage, "https://aistudio.google.com/usage"),
                link(.billing, "https://aistudio.google.com/app/billing"),
                link(.dashboard, "https://aistudio.google.com"),
                link(.status, "https://status.cloud.google.com")
            ]
        ),
        ProviderMetadata(
            id: .deepSeek,
            displayName: "DeepSeek",
            systemImageName: "wave.3.right.circle",
            credentialHelp: "A standard API key provides the official current balance, but not cost history.",
            capabilities: [.balance],
            externalLinks: [
                link(.usage, "https://platform.deepseek.com/usage"),
                link(.billing, "https://platform.deepseek.com/top_up"),
                link(.dashboard, "https://platform.deepseek.com"),
                link(.status, "https://status.deepseek.com")
            ]
        )
    ]

    static func metadata(for id: ProviderID) -> ProviderMetadata? {
        all.first { $0.id == id }
    }

    private static func link(_ kind: ExternalLink.Kind, _ value: String) -> ExternalLink {
        ExternalLink(kind: kind, url: URL(string: value)!)
    }
}
