import Foundation

final class ProviderTargetFactory: Sendable {
    private let credentialStore: any CredentialStoring
    private let configurations: [ProviderConfiguration]
    private let now: @Sendable () -> Date

    init(
        credentialStore: any CredentialStoring = KeychainStore(),
        openAIProvider: any ProviderClient = OpenAIProvider(),
        anthropicProvider: any ProviderClient = AnthropicProvider(),
        deepSeekProvider: any ProviderClient = DeepSeekProvider(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        configurations = [
            ProviderConfiguration(
                provider: openAIProvider,
                minimumInterval: 15 * 60,
                usesReportingWindow: true
            ),
            ProviderConfiguration(
                provider: anthropicProvider,
                minimumInterval: 15 * 60,
                usesReportingWindow: true
            ),
            ProviderConfiguration(
                provider: deepSeekProvider,
                minimumInterval: 5 * 60,
                usesReportingWindow: false
            )
        ]
        self.now = now
    }

    func makeTargets() -> [ProviderRefreshTarget] {
        configurations.compactMap { configuration in
            let provider = configuration.provider
            let identity = CredentialIdentity(providerID: provider.providerID)
            guard let credential = try? credentialStore.read(for: identity) else {
                return nil
            }

            return ProviderRefreshTarget(
                providerID: provider.providerID,
                generation: 0,
                minimumInterval: configuration.minimumInterval,
                automaticRefreshEnabled: true,
                fetch: { [now, usesReportingWindow = configuration.usesReportingWindow] in
                    try await provider.fetch(
                        ProviderFetchRequest(
                            purpose: .full,
                            reportingInterval: usesReportingWindow
                                ? Self.thirtyDayUTCInterval(containing: now())
                                : nil
                        ),
                        credential: credential
                    )
                },
                generationIsCurrent: { [credentialStore] _ in
                    (try? credentialStore.read(for: identity)) == credential
                }
            )
        }
    }

    private static func thirtyDayUTCInterval(containing date: Date) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        return DateInterval(start: start, end: end)
    }
}

private extension ProviderTargetFactory {
    struct ProviderConfiguration: Sendable {
        let provider: any ProviderClient
        let minimumInterval: TimeInterval
        let usesReportingWindow: Bool
    }
}
