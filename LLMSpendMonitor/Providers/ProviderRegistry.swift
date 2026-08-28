import Foundation

enum ProviderIntegrationAvailability: Equatable, Sendable {
    case available
    case planned
    case unavailable
}

struct ProviderMetadata: Identifiable, Equatable, Sendable {
    let id: ProviderID
    let displayName: String
    let systemImageName: String
    let credentialHelp: String
    let capabilities: Set<ProviderCapability>
    let externalLinks: [ExternalLink]
    let integrationAvailability: ProviderIntegrationAvailability
    let isVisibleByDefault: Bool
}

enum ProviderRegistry {
    private static let hiddenProviderIDs: Set<ProviderID> = [.gemini, .perplexity]

    static let all: [ProviderMetadata] = [
        ProviderMetadata(
            id: .openAI,
            displayName: "OpenAI",
            systemImageName: "circle.hexagongrid",
            credentialHelp: "Requires an Organization Admin API key for official usage and cost reports.",
            capabilities: [.officialCostHistory, .tokenUsage, .modelBreakdown],
            externalLinks: [
                link(.usage, "https://platform.openai.com/usage"),
                link(.billing, "https://platform.openai.com/settings/organization/billing/overview"),
                link(.dashboard, "https://platform.openai.com/settings/organization/general"),
                link(.status, "https://status.openai.com")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: true
        ),
        ProviderMetadata(
            id: .anthropic,
            displayName: "Anthropic",
            systemImageName: "sparkles",
            credentialHelp: "Requires a Console Admin API key for official usage and cost reports.",
            capabilities: [.officialCostHistory, .tokenUsage, .modelBreakdown],
            externalLinks: [
                link(.usage, "https://console.anthropic.com/settings/usage"),
                link(.billing, "https://console.anthropic.com/settings/billing"),
                link(.dashboard, "https://console.anthropic.com"),
                link(.status, "https://status.anthropic.com")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: true
        ),
        ProviderMetadata(
            id: .gemini,
            displayName: "Gemini",
            systemImageName: "diamond",
            credentialHelp: "Use any standard Gemini API key. Spender detects Free or Paid Tier automatically; read-only Google Cloud access adds official token and model usage.",
            capabilities: [.credentialValidation, .tokenUsage, .modelBreakdown],
            externalLinks: [
                link(.usage, "https://aistudio.google.com/usage"),
                link(.billing, "https://aistudio.google.com/app/billing"),
                link(.dashboard, "https://aistudio.google.com"),
                link(.status, "https://status.cloud.google.com")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: false
        ),
        ProviderMetadata(
            id: .deepSeek,
            displayName: "DeepSeek",
            systemImageName: "wave.3.right.circle",
            credentialHelp: "A standard API key provides the official current balance. Spender estimates daily spend from saved balance decreases because DeepSeek does not expose cost history via API.",
            capabilities: [.balance, .estimatedCostHistory],
            externalLinks: [
                link(.usage, "https://platform.deepseek.com/usage"),
                link(.billing, "https://platform.deepseek.com/top_up"),
                link(.dashboard, "https://platform.deepseek.com"),
                link(.status, "https://status.deepseek.com")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: true
        ),
        ProviderMetadata(
            id: .kimi,
            displayName: "Kimi",
            systemImageName: "moon.stars",
            credentialHelp: "A standard Moonshot API key provides the official current balance. Kimi does not expose aggregate spend history via API.",
            capabilities: [.balance],
            externalLinks: [
                link(.usage, "https://platform.moonshot.ai/console/info-center/usage"),
                link(.billing, "https://platform.moonshot.ai/console/info-center"),
                link(.dashboard, "https://platform.moonshot.ai/console")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: false
        ),
        ProviderMetadata(
            id: .qwen,
            displayName: "Qwen",
            systemImageName: "aqi.medium",
            credentialHelp: "Use a pay-as-you-go Model Studio API key and its API Host. Token Plan keys are not supported. Read-only billing access provides account balance and Qwen spend.",
            capabilities: [.balance, .credentialValidation, .officialCostHistory],
            externalLinks: [
                link(.usage, "https://modelstudio.console.alibabacloud.com/?tab=dashboard#/model-usage"),
                link(.billing, "https://usercenter2-intl.aliyun.com/billing/#/account/overview"),
                link(.dashboard, "https://modelstudio.console.alibabacloud.com/")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: false
        ),
        ProviderMetadata(
            id: .xAI,
            displayName: "xAI · Grok",
            systemImageName: "xmark",
            credentialHelp: "Requires a team-scoped xAI Management API key with read access to billing. Spender reads the official prepaid balance and daily USD usage.",
            capabilities: [.balance, .officialCostHistory, .modelBreakdown],
            externalLinks: [
                link(.usage, "https://console.x.ai/team/default/usage"),
                link(.billing, "https://console.x.ai/team/default/billing"),
                link(.dashboard, "https://console.x.ai/team/default/settings/management-keys"),
                link(.status, "https://status.x.ai")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: false
        ),
        ProviderMetadata(
            id: .mistral,
            displayName: "Mistral AI",
            systemImageName: "wind",
            credentialHelp: "Requires a dedicated Enterprise Admin API key from Mistral Backoffice. A standard Studio API key cannot read financial data. Spender shows the official remaining monthly spending limit.",
            capabilities: [.balance],
            externalLinks: [
                link(.usage, "https://admin.mistral.ai/api/usage"),
                link(.billing, "https://admin.mistral.ai/subscriptions/billing"),
                link(.dashboard, "https://backoffice.mistral.ai/"),
                link(.status, "https://status.mistral.ai")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: false
        ),
        ProviderMetadata(
            id: .openRouter,
            displayName: "OpenRouter",
            systemImageName: "arrow.triangle.branch",
            credentialHelp: "Requires an OpenRouter Management API key to read the official account-wide remaining credits.",
            capabilities: [.balance],
            externalLinks: [
                link(.usage, "https://openrouter.ai/activity"),
                link(.billing, "https://openrouter.ai/settings/credits"),
                link(.dashboard, "https://openrouter.ai/settings/management-keys")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: false
        ),
        ProviderMetadata(
            id: .perplexity,
            displayName: "Perplexity",
            systemImageName: "network",
            credentialHelp: "Perplexity does not expose account-wide Sonar API balance or usage through a public API. A standard API key only reports the cost of each request made with that key, so Spender cannot reconstruct activity from other apps.",
            capabilities: [],
            externalLinks: [
                link(.billing, "https://console.perplexity.ai/project/billing"),
                link(.dashboard, "https://console.perplexity.ai/project/api-keys"),
                link(.status, "https://status.perplexity.com")
            ],
            integrationAvailability: .unavailable,
            isVisibleByDefault: false
        )
    ]

    static var userFacing: [ProviderMetadata] {
        all.filter { !hiddenProviderIDs.contains($0.id) }
    }

    static func metadata(for id: ProviderID) -> ProviderMetadata? {
        all.first { $0.id == id }
    }

    private static func link(_ kind: ExternalLink.Kind, _ value: String) -> ExternalLink {
        ExternalLink(kind: kind, url: URL(string: value)!)
    }

}
