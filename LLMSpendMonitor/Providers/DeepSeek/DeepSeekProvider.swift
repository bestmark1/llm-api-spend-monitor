import Foundation

struct DeepSeekProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .deepSeek
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
        guard !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderClientError.invalidCredential
        }

        do {
            let response = try await fetchBalance(credential: credential)
            let balances = try response.balanceInfos
                .map(Self.makeBalance)
                .sorted { $0.total.value.currencyCode < $1.total.value.currencyCode }

            return try ProviderSnapshot(
                providerID: providerID,
                capabilities: capabilities,
                fetchedAt: now(),
                coverage: nil,
                buckets: [],
                balances: balances,
                issue: nil
            )
        } catch let error as ProviderClientError {
            throw error
        } catch {
            throw ProviderClientError.malformedResponse
        }
    }

    private func fetchBalance(credential: String) async throws -> BalanceResponse {
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            throw ProviderClientError.malformedResponse
        }

        do {
            let request = try HTTPRequest(
                method: .get,
                url: url,
                allowedOrigin: try HTTPOrigin(httpsURL: url),
                headers: [
                    "Authorization": "Bearer \(credential)",
                    "Accept": "application/json"
                ]
            )
            let response = try await httpClient.send(request)
            guard (200...299).contains(response.statusCode) else {
                throw HTTPClientError.httpStatus(response)
            }
            return try JSONDecoder().decode(BalanceResponse.self, from: response.body)
        } catch let error as ProviderClientError {
            throw error
        } catch let error as HTTPClientError {
            throw Self.map(error)
        } catch is DecodingError {
            throw ProviderClientError.malformedResponse
        } catch {
            throw ProviderClientError.unavailable
        }
    }

    private static func makeBalance(_ info: BalanceInfo) throws -> ProviderBalance {
        ProviderBalance(
            total: try money(info.totalBalance, currency: info.currency),
            granted: try money(info.grantedBalance, currency: info.currency),
            toppedUp: try money(info.toppedUpBalance, currency: info.currency)
        )
    }

    private static func money(_ value: String, currency: String) throws -> MoneyMetric {
        guard let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            throw ProviderClientError.malformedResponse
        }
        return MoneyMetric(
            value: try Money(amount: amount, currencyCode: currency),
            provenance: .official
        )
    }

    private static func map(_ error: HTTPClientError) -> ProviderClientError {
        switch error {
        case let .httpStatus(response):
            switch response.statusCode {
            case 401:
                .invalidCredential
            case 429:
                .rateLimited(
                    retryAfterSeconds: response.header(named: "retry-after").flatMap(TimeInterval.init)
                )
            default:
                .unavailable
            }
        case let .transport(code):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed:
                .offline
            default:
                .unavailable
            }
        case .invalidRequest, .invalidResponse, .responseTooLarge,
             .insecureURL, .disallowedOrigin, .crossOriginRedirect:
            .malformedResponse
        case .cancelled:
            .unavailable
        }
    }
}

private extension DeepSeekProvider {
    struct BalanceResponse: Decodable {
        let isAvailable: Bool
        let balanceInfos: [BalanceInfo]

        private enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    struct BalanceInfo: Decodable {
        let currency: String
        let totalBalance: String
        let grantedBalance: String
        let toppedUpBalance: String

        private enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }
}
