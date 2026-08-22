import Foundation

struct OpenRouterProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .openRouter
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
        guard !credential.isEmpty else { throw ProviderClientError.invalidCredential }
        let url = URL(string: "https://openrouter.ai/api/v1/credits")!

        do {
            let response = try await httpClient.send(
                try HTTPRequest(
                    method: .get,
                    url: url,
                    allowedOrigin: try HTTPOrigin(httpsURL: url),
                    headers: ["Authorization": "Bearer \(credential)"]
                )
            )
            let payload = try JSONDecoder().decode(CreditsResponse.self, from: response.body)
            let remaining = max(payload.data.totalCredits - payload.data.totalUsage, 0)
            let balance = ProviderBalance(
                total: MoneyMetric(
                    value: try Money(amount: remaining, currencyCode: "USD"),
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
                issue: nil
            )
        } catch let error as ProviderClientError {
            throw error
        } catch let error as HTTPClientError {
            throw ProviderErrorMapper.map(error, forbidden: .insufficientPermissions)
        } catch is DecodingError {
            throw ProviderClientError.malformedResponse
        } catch {
            throw ProviderClientError.unavailable
        }
    }
}

private extension OpenRouterProvider {
    struct CreditsResponse: Decodable {
        let data: Credits
    }

    struct Credits: Decodable {
        let totalCredits: Decimal
        let totalUsage: Decimal

        private enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
}
