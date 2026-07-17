import Foundation

enum RefreshTrigger: Equatable, Sendable {
    case launch
    case panelOpen
    case manual
    case timer
    case wake
    case unlock
    case credentialValidation
}

struct ProviderRefreshTarget: Sendable {
    let providerID: ProviderID
    let generation: UInt64
    let minimumInterval: TimeInterval
    let automaticRefreshEnabled: Bool
    let fetch: @Sendable () async throws -> ProviderSnapshot
    let generationIsCurrent: @Sendable (UInt64) async -> Bool
}
