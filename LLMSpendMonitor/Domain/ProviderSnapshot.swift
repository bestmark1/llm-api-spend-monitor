import Foundation

enum MetricProvenance: String, Codable, Hashable, Sendable {
    case official
    case userBudget
    case unavailable
    case estimated
}

struct MoneyMetric: Codable, Equatable, Sendable {
    let value: Money
    let provenance: MetricProvenance
}

struct TokenUsage: Codable, Equatable, Sendable {
    let inputTokens: Int64
    let outputTokens: Int64
    let cachedInputTokens: Int64
    let provenance: MetricProvenance
}

struct ModelUsage: Codable, Equatable, Sendable {
    let modelID: String
    let cost: MoneyMetric?
    let tokenUsage: TokenUsage?
}

struct PeriodBucket: Codable, Equatable, Sendable {
    let start: Date
    let end: Date
    let cost: MoneyMetric?
    let tokenUsage: TokenUsage?
    let modelBreakdown: [ModelUsage]

    init(
        start: Date,
        end: Date,
        cost: MoneyMetric? = nil,
        tokenUsage: TokenUsage? = nil,
        modelBreakdown: [ModelUsage] = []
    ) {
        self.start = start
        self.end = end
        self.cost = cost
        self.tokenUsage = tokenUsage
        self.modelBreakdown = modelBreakdown
    }
}

struct ProviderBalance: Codable, Equatable, Sendable {
    let total: MoneyMetric
    let granted: MoneyMetric?
    let toppedUp: MoneyMetric?
}

struct ReportingCoverage: Codable, Equatable, Sendable {
    enum Completeness: String, Codable, Sendable {
        case complete
        case partial
    }

    let start: Date
    let through: Date
    let completeness: Completeness
}

enum ProviderIssue: String, Codable, Equatable, Sendable {
    case authentication
    case balanceUnavailable
    case usageUnavailable
    case insufficientPermissions
    case rateLimited
    case offline
    case keychainLocked
    case malformedResponse
    case noSpendingLimit
    case providerUnavailable
    case partialData
    case spendingLimitReached
}

struct ProviderSnapshot: Codable, Equatable, Sendable {
    enum ValidationError: Error, Equatable {
        case unsupportedMetric(ProviderCapability)
        case nonOfficialProviderMoney
        case nonOfficialProviderTokens
        case invalidCoverage
        case invalidBucket
        case invalidRetryAfter
    }

    let providerID: ProviderID
    let capabilities: Set<ProviderCapability>
    let fetchedAt: Date
    let coverage: ReportingCoverage?
    let buckets: [PeriodBucket]
    let balances: [ProviderBalance]
    let issue: ProviderIssue?
    let retryAfterSeconds: TimeInterval?

    init(
        providerID: ProviderID,
        capabilities: Set<ProviderCapability>,
        fetchedAt: Date,
        coverage: ReportingCoverage?,
        buckets: [PeriodBucket],
        balances: [ProviderBalance],
        issue: ProviderIssue?,
        retryAfterSeconds: TimeInterval? = nil
    ) throws {
        if let retryAfterSeconds, !retryAfterSeconds.isFinite || retryAfterSeconds < 0 {
            throw ValidationError.invalidRetryAfter
        }
        let requiredCapabilities = Self.requiredCapabilities(for: buckets, balances: balances)
        if let missingCapability = requiredCapabilities
            .subtracting(capabilities)
            .sorted(by: { $0.rawValue < $1.rawValue })
            .first {
            throw ValidationError.unsupportedMetric(missingCapability)
        }

        guard Self.providerMoney(in: buckets, balances: balances).allSatisfy({
            $0.provenance == .official || $0.provenance == .estimated
        }) else {
            throw ValidationError.nonOfficialProviderMoney
        }

        guard Self.providerTokens(in: buckets).allSatisfy({
            $0.provenance == .official
                && $0.inputTokens >= 0
                && $0.outputTokens >= 0
                && $0.cachedInputTokens >= 0
        }) else {
            throw ValidationError.nonOfficialProviderTokens
        }

        if let coverage {
            guard coverage.start <= coverage.through else {
                throw ValidationError.invalidCoverage
            }
        } else if !buckets.isEmpty {
            throw ValidationError.invalidCoverage
        }

        guard buckets.allSatisfy({ bucket in
            guard bucket.start < bucket.end else { return false }
            guard let coverage else { return false }
            return bucket.start >= coverage.start && bucket.end <= coverage.through
        }) else {
            throw ValidationError.invalidBucket
        }

        self.providerID = providerID
        self.capabilities = capabilities
        self.fetchedAt = fetchedAt
        self.coverage = coverage
        self.buckets = buckets
        self.balances = balances
        self.issue = issue
        self.retryAfterSeconds = retryAfterSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case providerID
        case capabilities
        case fetchedAt
        case coverage
        case buckets
        case balances
        case issue
        case retryAfterSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            providerID: container.decode(ProviderID.self, forKey: .providerID),
            capabilities: container.decode(Set<ProviderCapability>.self, forKey: .capabilities),
            fetchedAt: container.decode(Date.self, forKey: .fetchedAt),
            coverage: container.decodeIfPresent(ReportingCoverage.self, forKey: .coverage),
            buckets: container.decode([PeriodBucket].self, forKey: .buckets),
            balances: container.decode([ProviderBalance].self, forKey: .balances),
            issue: container.decodeIfPresent(ProviderIssue.self, forKey: .issue),
            retryAfterSeconds: container.decodeIfPresent(TimeInterval.self, forKey: .retryAfterSeconds)
        )
    }

    private static func requiredCapabilities(
        for buckets: [PeriodBucket],
        balances: [ProviderBalance]
    ) -> Set<ProviderCapability> {
        var capabilities: Set<ProviderCapability> = []

        let costMetrics = buckets.flatMap { bucket in
            [bucket.cost].compactMap { $0 } + bucket.modelBreakdown.compactMap(\.cost)
        }
        if costMetrics.contains(where: { $0.provenance == .official }) {
            capabilities.insert(.officialCostHistory)
        }
        if costMetrics.contains(where: { $0.provenance == .estimated }) {
            capabilities.insert(.estimatedCostHistory)
        }
        if buckets.contains(where: { $0.tokenUsage != nil || $0.modelBreakdown.contains(where: { $0.tokenUsage != nil }) }) {
            capabilities.insert(.tokenUsage)
        }
        if buckets.contains(where: { !$0.modelBreakdown.isEmpty }) {
            capabilities.insert(.modelBreakdown)
        }
        if !balances.isEmpty {
            capabilities.insert(.balance)
        }

        return capabilities
    }

    private static func providerMoney(
        in buckets: [PeriodBucket],
        balances: [ProviderBalance]
    ) -> [MoneyMetric] {
        let bucketMoney = buckets.flatMap { bucket in
            [bucket.cost].compactMap { $0 } + bucket.modelBreakdown.compactMap(\.cost)
        }
        let balanceMoney = balances.flatMap { balance in
            [balance.total, balance.granted, balance.toppedUp].compactMap { $0 }
        }
        return bucketMoney + balanceMoney
    }

    private static func providerTokens(in buckets: [PeriodBucket]) -> [TokenUsage] {
        buckets.flatMap { bucket in
            [bucket.tokenUsage].compactMap { $0 } + bucket.modelBreakdown.compactMap(\.tokenUsage)
        }
    }
}
