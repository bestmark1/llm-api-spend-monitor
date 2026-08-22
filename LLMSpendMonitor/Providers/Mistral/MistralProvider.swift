import Foundation

struct MistralProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .mistral
    let capabilities: Set<ProviderCapability> = [.balance]

    private let httpClient: any HTTPClient
    private let now: @Sendable () -> Date

    init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.now = now
    }

    func fetch(
        _ request: ProviderFetchRequest,
        credential: String
    ) async throws -> ProviderSnapshot {
        let credential = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else {
            throw ProviderClientError.invalidCredential
        }
        let url = URL(string: "https://api.mistral.ai/v1/admin/spend-limit")!

        do {
            let response = try await httpClient.send(
                try HTTPRequest(
                    method: .get,
                    url: url,
                    allowedOrigin: try HTTPOrigin(httpsURL: url),
                    headers: [
                        "Accept": "application/json",
                        "x-api-key": credential
                    ]
                )
            )
            let payload = try JSONDecoder().decode(SpendLimitResponse.self, from: response.body)
            let completion = payload.limits.completion

            if completion.noMonthlyLimit == true {
                return try ProviderSnapshot(
                    providerID: providerID,
                    capabilities: capabilities,
                    fetchedAt: now(),
                    coverage: nil,
                    buckets: [],
                    balances: [],
                    issue: .noSpendingLimit
                )
            }
            guard let limit = completion.usageLimit else {
                throw ProviderClientError.malformedResponse
            }

            let usage = completion.totalUsage ?? completion.usage ?? 0
            guard limit >= 0, usage >= 0 else {
                throw ProviderClientError.malformedResponse
            }
            let remaining = max(limit - usage, 0)
            let balance = ProviderBalance(
                total: MoneyMetric(
                    value: try Money(
                        amount: remaining,
                        currencyCode: payload.limits.currency
                    ),
                    provenance: .official
                ),
                granted: nil,
                toppedUp: nil
            )

            return try ProviderSnapshot(
                providerID: providerID,
                capabilities: capabilities,
                fetchedAt: now(),
                coverage: nil,
                buckets: [],
                balances: [balance],
                issue: completion.monthlyLimitReached ? .spendingLimitReached : nil
            )
        } catch let error as ProviderClientError {
            throw error
        } catch let error as HTTPClientError {
            throw ProviderErrorMapper.map(error, forbidden: .insufficientPermissions)
        } catch is DecodingError {
            throw ProviderClientError.malformedResponse
        } catch {
            throw ProviderClientError.malformedResponse
        }
    }
}

private extension MistralProvider {
    struct SpendLimitResponse: Decodable {
        let limits: Limits
    }

    struct Limits: Decodable {
        let completion: CompletionLimits
        let currency: String
    }

    struct CompletionLimits: Decodable {
        let monthlyLimitReached: Bool
        let noMonthlyLimit: Bool?
        let usage: Decimal?
        let totalUsage: Decimal?
        let usageLimit: Decimal?

        private enum CodingKeys: String, CodingKey {
            case monthlyLimitReached = "monthly_limit_reached"
            case noMonthlyLimit = "no_monthly_limit"
            case usage
            case totalUsage = "total_usage"
            case usageLimit = "usage_limit"
        }
    }
}
