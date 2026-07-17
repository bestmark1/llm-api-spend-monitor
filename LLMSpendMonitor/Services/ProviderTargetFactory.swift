import Foundation

final class ProviderTargetFactory: Sendable {
    private let credentialStore: any CredentialStoring
    private let providers: [any ProviderClient]
    private let now: @Sendable () -> Date

    init(
        credentialStore: any CredentialStoring = KeychainStore(),
        openAIProvider: any ProviderClient = OpenAIProvider(),
        anthropicProvider: any ProviderClient = AnthropicProvider(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        providers = [openAIProvider, anthropicProvider]
        self.now = now
    }

    func makeTargets() -> [ProviderRefreshTarget] {
        providers.compactMap { provider in
            let identity = CredentialIdentity(providerID: provider.providerID)
            guard let credential = try? credentialStore.read(for: identity) else {
                return nil
            }

            return ProviderRefreshTarget(
                providerID: provider.providerID,
                generation: 0,
                minimumInterval: 15 * 60,
                automaticRefreshEnabled: true,
                fetch: { [now] in
                    try await provider.fetch(
                        ProviderFetchRequest(
                            purpose: .full,
                            reportingInterval: Self.thirtyDayUTCInterval(containing: now())
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
