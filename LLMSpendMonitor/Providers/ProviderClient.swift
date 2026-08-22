import Foundation

struct ProviderFetchRequest: Equatable, Sendable {
    enum Purpose: Equatable, Sendable {
        case credentialValidation
        case incremental
        case full
    }

    let purpose: Purpose
    let reportingInterval: DateInterval?
}

enum ProviderClientError: Error, Equatable, Sendable {
    case invalidCredential
    case insufficientPermissions
    case rateLimited(retryAfterSeconds: TimeInterval?)
    case offline
    case malformedResponse
    case unavailable
}

protocol ProviderClient: Sendable {
    var providerID: ProviderID { get }
    var capabilities: Set<ProviderCapability> { get }

    func fetch(
        _ request: ProviderFetchRequest,
        credential: String
    ) async throws -> ProviderSnapshot
}

enum ProviderErrorMapper {
    static func map(
        _ error: HTTPClientError,
        forbidden: ProviderClientError = .unavailable
    ) -> ProviderClientError {
        switch error {
        case let .httpStatus(response):
            switch response.statusCode {
            case 401:
                .invalidCredential
            case 403:
                forbidden
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
