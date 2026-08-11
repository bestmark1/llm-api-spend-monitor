import Foundation

enum ProviderIntegrationAvailability: Equatable, Sendable {
    case available
    case planned
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
            credentialHelp: "A Gemini API key validates access. Basic keys do not expose official cost or balance data.",
            capabilities: [.credentialValidation],
            externalLinks: [
                link(.usage, "https://aistudio.google.com/usage"),
                link(.billing, "https://aistudio.google.com/app/billing"),
                link(.dashboard, "https://aistudio.google.com"),
                link(.status, "https://status.cloud.google.com")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: true
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
            ],
            integrationAvailability: .available,
            isVisibleByDefault: true
        ),
        plannedProvider(
            id: .kimi,
            displayName: "Kimi",
            systemImageName: "moon.stars",
            dashboardURL: "https://platform.moonshot.ai/console"
        ),
        ProviderMetadata(
            id: .qwen,
            displayName: "Qwen",
            systemImageName: "aqi.medium",
            credentialHelp: "Add a Model Studio API key and its official OpenAI-compatible Base URL. The key can be verified, but account-wide spend requires separate Alibaba Cloud billing credentials.",
            capabilities: [.credentialValidation],
            externalLinks: [
                link(.usage, "https://modelstudio.console.alibabacloud.com/?tab=dashboard#/model-usage"),
                link(.billing, "https://usercenter2-intl.aliyun.com/billing/#/account/overview"),
                link(.dashboard, "https://modelstudio.console.alibabacloud.com/")
            ],
            integrationAvailability: .available,
            isVisibleByDefault: false
        ),
        plannedProvider(
            id: .xAI,
            displayName: "xAI · Grok",
            systemImageName: "xmark",
            dashboardURL: "https://console.x.ai/"
        ),
        plannedProvider(
            id: .mistral,
            displayName: "Mistral AI",
            systemImageName: "wind",
            dashboardURL: "https://console.mistral.ai/"
        ),
        plannedProvider(
            id: .openRouter,
            displayName: "OpenRouter",
            systemImageName: "arrow.triangle.branch",
            dashboardURL: "https://openrouter.ai/activity"
        ),
        plannedProvider(
            id: .perplexity,
            displayName: "Perplexity",
            systemImageName: "network",
            dashboardURL: "https://www.perplexity.ai/settings/api"
        )
    ]

    static func metadata(for id: ProviderID) -> ProviderMetadata? {
        all.first { $0.id == id }
    }

    private static func link(_ kind: ExternalLink.Kind, _ value: String) -> ExternalLink {
        ExternalLink(kind: kind, url: URL(string: value)!)
    }

    private static func plannedProvider(
        id: ProviderID,
        displayName: String,
        systemImageName: String,
        dashboardURL: String
    ) -> ProviderMetadata {
        ProviderMetadata(
            id: id,
            displayName: displayName,
            systemImageName: systemImageName,
            credentialHelp: "Spending integration is planned but not available yet.",
            capabilities: [],
            externalLinks: [link(.dashboard, dashboardURL)],
            integrationAvailability: .planned,
            isVisibleByDefault: false
        )
    }
}
