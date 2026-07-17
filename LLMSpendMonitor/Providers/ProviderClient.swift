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
