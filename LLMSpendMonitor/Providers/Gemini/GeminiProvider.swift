import Foundation

struct GeminiProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .gemini
    let capabilities: Set<ProviderCapability> = [.credentialValidation]

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
            _ = try await listModels(credential: credential)
            return try ProviderSnapshot(
                providerID: providerID,
                capabilities: capabilities,
                fetchedAt: now(),
                coverage: nil,
                buckets: [],
                balances: [],
                issue: nil
            )
        } catch let error as ProviderClientError {
            throw error
        } catch {
            throw ProviderClientError.malformedResponse
        }
    }

    private func listModels(credential: String) async throws -> ModelsResponse {
        guard var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models"
        ) else {
            throw ProviderClientError.malformedResponse
        }
        components.queryItems = [URLQueryItem(name: "pageSize", value: "1")]
        guard let url = components.url else {
            throw ProviderClientError.malformedResponse
        }

        do {
            let request = try HTTPRequest(
                method: .get,
                url: url,
                allowedOrigin: try HTTPOrigin(httpsURL: url),
                headers: [
                    "x-goog-api-key": credential,
                    "Accept": "application/json"
                ]
            )
            let response = try await httpClient.send(request)
            guard (200...299).contains(response.statusCode) else {
                throw HTTPClientError.httpStatus(response)
            }
            return try JSONDecoder().decode(ModelsResponse.self, from: response.body)
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

    private static func map(_ error: HTTPClientError) -> ProviderClientError {
        switch error {
        case let .httpStatus(response):
            switch response.statusCode {
            case 400, 401:
                .invalidCredential
            case 403:
                .insufficientPermissions
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

private extension GeminiProvider {
    struct ModelsResponse: Decodable {
        let models: [Model]?
    }

    struct Model: Decodable {
        let name: String
    }
}
