import Foundation

struct KimiProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .kimi
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
        let url = URL(string: "https://api.moonshot.ai/v1/users/me/balance")!

        do {
            let response = try await httpClient.send(
                try HTTPRequest(
                    method: .get,
                    url: url,
                    allowedOrigin: try HTTPOrigin(httpsURL: url),
                    headers: ["Authorization": "Bearer \(credential)"]
                )
            )
            let payload = try JSONDecoder().decode(BalanceResponse.self, from: response.body)
            guard payload.status else { throw ProviderClientError.malformedResponse }

            return try ProviderSnapshot(
                providerID: providerID,
                capabilities: capabilities,
                fetchedAt: now(),
                coverage: nil,
                buckets: [],
                balances: [
                    ProviderBalance(
                        total: try Self.money(payload.data.availableBalance),
                        granted: try Self.money(payload.data.voucherBalance),
                        toppedUp: try Self.money(payload.data.cashBalance)
                    )
                ],
                issue: nil
            )
        } catch let error as ProviderClientError {
            throw error
        } catch let error as HTTPClientError {
            throw ProviderErrorMapper.map(error)
        } catch is DecodingError {
            throw ProviderClientError.malformedResponse
        } catch {
            throw ProviderClientError.unavailable
        }
    }

    private static func money(_ amount: Decimal) throws -> MoneyMetric {
        MoneyMetric(
            value: try Money(amount: amount, currencyCode: "USD"),
            provenance: .official
        )
    }
}

private extension KimiProvider {
    struct BalanceResponse: Decodable {
        let data: BalanceData
        let status: Bool
    }

    struct BalanceData: Decodable {
        let availableBalance: Decimal
        let voucherBalance: Decimal
        let cashBalance: Decimal

        private enum CodingKeys: String, CodingKey {
            case availableBalance = "available_balance"
            case voucherBalance = "voucher_balance"
            case cashBalance = "cash_balance"
        }
    }
}
