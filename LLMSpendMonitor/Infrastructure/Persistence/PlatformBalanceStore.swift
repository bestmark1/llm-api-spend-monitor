import Foundation

struct PlatformBalanceCostAnchor: Codable, Equatable, Sendable {
    let start: Date
    let end: Date
    let cost: Money
}

struct PlatformBalanceCheckpoint: Codable, Equatable, Sendable {
    let providerID: ProviderID
    let enteredBalance: Money
    let synchronizedAt: Date
    let deductedSpend: Money
    let costAnchors: [PlatformBalanceCostAnchor]
}

protocol PlatformBalanceStoring: AnyObject {
    func load() -> [ProviderID: PlatformBalanceCheckpoint]
    func save(_ checkpoints: [ProviderID: PlatformBalanceCheckpoint])
}

final class UserDefaultsPlatformBalanceStore: PlatformBalanceStoring {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "platform-balances-v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [ProviderID: PlatformBalanceCheckpoint] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([ProviderID: PlatformBalanceCheckpoint].self, from: data)) ?? [:]
    }

    func save(_ checkpoints: [ProviderID: PlatformBalanceCheckpoint]) {
        guard let data = try? JSONEncoder().encode(checkpoints) else { return }
        defaults.set(data, forKey: key)
    }
}
