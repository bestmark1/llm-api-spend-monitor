import Foundation

enum QwenAPIEndpointError: Error, Equatable {
    case invalidURL
    case unsupportedHost
    case unsupportedPath
}

struct QwenAPIEndpoint: Equatable, Sendable {
    static let defaultValue = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"

    let baseURL: URL

    init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: trimmed),
            components.scheme?.lowercased() == "https",
            let host = components.host?.lowercased(),
            !host.isEmpty,
            components.port == nil || components.port == 443,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            throw QwenAPIEndpointError.invalidURL
        }

        guard Self.allowedHosts.contains(host) || host.hasSuffix(".maas.aliyuncs.com") else {
            throw QwenAPIEndpointError.unsupportedHost
        }

        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard components.path == "/compatible-mode/v1" else {
            throw QwenAPIEndpointError.unsupportedPath
        }
        guard let normalizedURL = components.url else {
            throw QwenAPIEndpointError.invalidURL
        }

        baseURL = normalizedURL
    }

    var modelsURL: URL {
        baseURL.appending(path: "models")
    }

    private static let allowedHosts: Set<String> = [
        "dashscope.aliyuncs.com",
        "dashscope-intl.aliyuncs.com",
        "dashscope-us.aliyuncs.com",
        "token-plan.cn-beijing.maas.aliyuncs.com"
    ]
}

struct QwenProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .qwen
    let capabilities: Set<ProviderCapability> = [.credentialValidation]

    private let httpClient: any HTTPClient
    private let endpointStore: any ProviderEndpointStoring
    private let now: @Sendable () -> Date

    init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        endpointStore: any ProviderEndpointStoring = UserDefaultsProviderEndpointStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.endpointStore = endpointStore
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
            let endpoint = try QwenAPIEndpoint(
                endpointStore.loadEndpoint(for: providerID) ?? QwenAPIEndpoint.defaultValue
            )
            _ = try await listModels(endpoint: endpoint, credential: credential)
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
        } catch is QwenAPIEndpointError {
            throw ProviderClientError.malformedResponse
        } catch {
            throw ProviderClientError.malformedResponse
        }
    }

    private func listModels(
        endpoint: QwenAPIEndpoint,
        credential: String
    ) async throws -> ModelsResponse {
        let url = endpoint.modelsURL

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
            return try JSONDecoder().decode(ModelsResponse.self, from: response.body)
        } catch let error as HTTPClientError {
            throw Self.map(error)
        } catch is DecodingError {
            throw ProviderClientError.malformedResponse
        } catch let error as ProviderClientError {
            throw error
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

private extension QwenProvider {
    struct ModelsResponse: Decodable {
        let data: [Model]
    }

    struct Model: Decodable {
        let id: String
    }
}
