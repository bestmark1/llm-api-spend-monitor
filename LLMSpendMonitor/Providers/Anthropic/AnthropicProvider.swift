import Foundation

struct AnthropicProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .anthropic
    let capabilities: Set<ProviderCapability> = [
        .officialCostHistory,
        .tokenUsage,
        .modelBreakdown
    ]

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
        guard let interval = request.reportingInterval, interval.start < interval.end else {
            throw ProviderClientError.malformedResponse
        }

        let pageLimit = Self.pageLimit(for: request.purpose)
        let costResult = try await fetchCosts(
            interval: interval,
            credential: credential,
            pageLimit: pageLimit
        )
        let usageResult: UsagePageResult?
        var retryAfterSeconds: TimeInterval?
        do {
            let candidate = try await fetchUsage(
                interval: interval, credential: credential, pageLimit: pageLimit
            )
            // Validate usage independently so malformed metrics cannot discard valid costs.
            _ = try ProviderSnapshot(
                providerID: providerID,
                capabilities: capabilities,
                fetchedAt: now(),
                coverage: ReportingCoverage(
                    start: interval.start,
                    through: interval.end,
                    completeness: candidate.isComplete ? .complete : .partial
                ),
                buckets: try Self.makeBuckets(costs: [:], usage: candidate.buckets),
                balances: [],
                issue: nil
            )
            usageResult = candidate
        } catch {
            usageResult = nil
            if case let ProviderClientError.rateLimited(retryAfter) = error {
                retryAfterSeconds = retryAfter.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 30
            }
        }
        let usageComplete = usageResult?.isComplete == true
        // Priority Tier costs are absent from this API. Unknown usage scope stays partial.
        let hasPriorityTier = usageResult?.hasPriorityTier == true
        let isComplete = costResult.isComplete && usageComplete && !hasPriorityTier
        let issue: ProviderIssue? = !costResult.isComplete || hasPriorityTier ? .partialData
            : (usageComplete ? nil : .usageUnavailable)

        do {
            return try ProviderSnapshot(
                providerID: providerID,
                capabilities: capabilities,
                fetchedAt: now(),
                coverage: ReportingCoverage(
                    start: interval.start,
                    through: interval.end,
                    completeness: isComplete ? .complete : .partial
                ),
                buckets: try Self.makeBuckets(
                    costs: costResult.buckets,
                    usage: usageComplete ? (usageResult?.buckets ?? [:]) : [:]
                ),
                balances: [],
                issue: issue,
                retryAfterSeconds: retryAfterSeconds
            )
        } catch let error as ProviderClientError {
            throw error
        } catch {
            throw ProviderClientError.malformedResponse
        }
    }

    private func fetchCosts(
        interval: DateInterval,
        credential: String,
        pageLimit: Int
    ) async throws -> PageResult<CostBucket> {
        var pageToken: String?
        var buckets: [BucketKey: CostBucket] = [:]

        for pageIndex in 0..<pageLimit {
            let page: Page<CostResult> = try await fetchPage(
                path: "/v1/organizations/cost_report",
                interval: interval,
                credential: credential,
                pageToken: pageToken,
                groupUsage: false
            )

            for bucket in page.data {
                let key = try Self.key(for: bucket)
                for result in bucket.results {
                    guard let amount = Decimal(
                        string: result.amount,
                        locale: Locale(identifier: "en_US_POSIX")
                    ) else {
                        throw ProviderClientError.malformedResponse
                    }
                    var aggregate = buckets[key] ?? CostBucket(
                        minorAmount: 0,
                        currency: result.currency
                    )
                    guard aggregate.currency.caseInsensitiveCompare(result.currency) == .orderedSame else {
                        throw ProviderClientError.malformedResponse
                    }
                    aggregate.minorAmount += amount
                    buckets[key] = aggregate
                }
            }

            guard page.hasMore else {
                return PageResult(buckets: buckets, isComplete: true)
            }
            guard pageIndex + 1 < pageLimit else {
                return PageResult(buckets: buckets, isComplete: false)
            }
            guard let nextPage = page.nextPage, !nextPage.isEmpty else {
                throw ProviderClientError.malformedResponse
            }
            pageToken = nextPage
        }

        return PageResult(buckets: buckets, isComplete: false)
    }

    private func fetchUsage(
        interval: DateInterval,
        credential: String,
        pageLimit: Int
    ) async throws -> UsagePageResult {
        var pageToken: String?
        var buckets: [BucketKey: UsageBucket] = [:]
        var hasPriorityTier = false

        for pageIndex in 0..<pageLimit {
            let page: Page<UsageResult> = try await fetchPage(
                path: "/v1/organizations/usage_report/messages",
                interval: interval,
                credential: credential,
                pageToken: pageToken,
                groupUsage: true
            )

            for bucket in page.data {
                let key = try Self.key(for: bucket)
                var aggregate = buckets[key] ?? UsageBucket()
                for result in bucket.results {
                    if result.serviceTier?.lowercased().hasPrefix("priority") == true {
                        hasPriorityTier = true
                    }
                    var input = result.uncachedInputTokens
                    input = try Self.adding(input, result.cacheCreation?.ephemeral1hInputTokens ?? 0)
                    input = try Self.adding(input, result.cacheCreation?.ephemeral5mInputTokens ?? 0)
                    input = try Self.adding(input, result.cacheReadInputTokens)
                    let tokens = TokenCount(
                        input: input,
                        output: result.outputTokens,
                        cachedInput: result.cacheReadInputTokens
                    )
                    try aggregate.total.add(tokens)

                    if let model = result.model?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !model.isEmpty {
                        var modelTokens = aggregate.models[model] ?? TokenCount()
                        try modelTokens.add(tokens)
                        aggregate.models[model] = modelTokens
                    }
                }
                buckets[key] = aggregate
            }

            guard page.hasMore else {
                return UsagePageResult(
                    buckets: buckets,
                    isComplete: true,
                    hasPriorityTier: hasPriorityTier
                )
            }
            guard pageIndex + 1 < pageLimit else {
                return UsagePageResult(
                    buckets: buckets,
                    isComplete: false,
                    hasPriorityTier: hasPriorityTier
                )
            }
            guard let nextPage = page.nextPage, !nextPage.isEmpty else {
                throw ProviderClientError.malformedResponse
            }
            pageToken = nextPage
        }

        return UsagePageResult(
            buckets: buckets,
            isComplete: false,
            hasPriorityTier: hasPriorityTier
        )
    }

    private func fetchPage<Result: Decodable>(
        path: String,
        interval: DateInterval,
        credential: String,
        pageToken: String?,
        groupUsage: Bool
    ) async throws -> Page<Result> {
        guard var components = URLComponents(string: "https://api.anthropic.com\(path)") else {
            throw ProviderClientError.malformedResponse
        }
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: Self.timestamp(interval.start)),
            URLQueryItem(name: "ending_at", value: Self.timestamp(interval.end)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]
        if groupUsage {
            components.queryItems?.append(URLQueryItem(name: "group_by[]", value: "model"))
            components.queryItems?.append(URLQueryItem(name: "group_by[]", value: "service_tier"))
        }
        if let pageToken {
            components.queryItems?.append(URLQueryItem(name: "page", value: pageToken))
        }
        guard let url = components.url else {
            throw ProviderClientError.malformedResponse
        }

        do {
            let request = try HTTPRequest(
                method: .get,
                url: url,
                allowedOrigin: try HTTPOrigin(httpsURL: url),
                headers: [
                    "x-api-key": credential,
                    "anthropic-version": "2023-06-01",
                    "Accept": "application/json"
                ]
            )
            let response = try await httpClient.send(request)
            guard (200...299).contains(response.statusCode) else {
                throw HTTPClientError.httpStatus(response)
            }
            let decoder = JSONDecoder()
            return try decoder.decode(Page<Result>.self, from: response.body)
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

    private static func makeBuckets(
        costs: [BucketKey: CostBucket],
        usage: [BucketKey: UsageBucket]
    ) throws -> [PeriodBucket] {
        let keys = Set(costs.keys).union(usage.keys).sorted {
            ($0.start, $0.end) < ($1.start, $1.end)
        }

        return try keys.map { key in
            let cost = try costs[key].map { bucket in
                MoneyMetric(
                    value: try Money(
                        amount: bucket.minorAmount / Decimal(100),
                        currencyCode: bucket.currency
                    ),
                    provenance: .official
                )
            }
            let tokenUsage = usage[key].map { Self.tokenUsage(from: $0.total) }
            let models = usage[key]?.models.keys.sorted().compactMap { model -> ModelUsage? in
                guard let tokens = usage[key]?.models[model] else { return nil }
                return ModelUsage(
                    modelID: model,
                    cost: nil,
                    tokenUsage: Self.tokenUsage(from: tokens)
                )
            } ?? []

            return PeriodBucket(
                start: key.start,
                end: key.end,
                cost: cost,
                tokenUsage: tokenUsage,
                modelBreakdown: models
            )
        }
    }

    private static func key<Result>(for bucket: APIBucket<Result>) throws -> BucketKey {
        guard
            let start = parseTimestamp(bucket.startingAt),
            let end = parseTimestamp(bucket.endingAt),
            start < end
        else {
            throw ProviderClientError.malformedResponse
        }
        return BucketKey(start: start, end: end)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func tokenUsage(from tokens: TokenCount) -> TokenUsage {
        TokenUsage(
            inputTokens: tokens.input,
            outputTokens: tokens.output,
            cachedInputTokens: tokens.cachedInput,
            provenance: .official
        )
    }

    private static func adding(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw ProviderClientError.malformedResponse }
        return result.partialValue
    }

    private static func pageLimit(for purpose: ProviderFetchRequest.Purpose) -> Int {
        switch purpose {
        case .credentialValidation: 1
        case .incremental: 2
        case .full: 10
        }
    }

}

private extension AnthropicProvider {
    struct Page<Result: Decodable>: Decodable {
        let data: [APIBucket<Result>]
        let hasMore: Bool
        let nextPage: String?

        private enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }

    struct APIBucket<Result: Decodable>: Decodable {
        let startingAt: String
        let endingAt: String
        let results: [Result]

        private enum CodingKeys: String, CodingKey {
            case startingAt = "starting_at"
            case endingAt = "ending_at"
            case results
        }
    }

    struct CostResult: Decodable {
        let amount: String
        let currency: String
    }

    struct UsageResult: Decodable {
        let uncachedInputTokens: Int64
        let cacheCreation: CacheCreation?
        let cacheReadInputTokens: Int64
        let outputTokens: Int64
        let model: String?
        let serviceTier: String?

        private enum CodingKeys: String, CodingKey {
            case uncachedInputTokens = "uncached_input_tokens"
            case cacheCreation = "cache_creation"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case outputTokens = "output_tokens"
            case model
            case serviceTier = "service_tier"
        }
    }

    struct CacheCreation: Decodable {
        let ephemeral1hInputTokens: Int64
        let ephemeral5mInputTokens: Int64

        private enum CodingKeys: String, CodingKey {
            case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
            case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
        }
    }

    struct BucketKey: Hashable {
        let start: Date
        let end: Date
    }

    struct CostBucket {
        var minorAmount: Decimal
        let currency: String
    }

    struct UsageBucket {
        var total = TokenCount()
        var models: [String: TokenCount] = [:]
    }

    struct TokenCount {
        var input: Int64 = 0
        var output: Int64 = 0
        var cachedInput: Int64 = 0

        mutating func add(_ other: TokenCount) throws {
            input = try AnthropicProvider.adding(input, other.input)
            output = try AnthropicProvider.adding(output, other.output)
            cachedInput = try AnthropicProvider.adding(cachedInput, other.cachedInput)
        }
    }

    struct PageResult<Bucket> {
        let buckets: [BucketKey: Bucket]
        let isComplete: Bool
    }

    struct UsagePageResult {
        let buckets: [BucketKey: UsageBucket]
        let isComplete: Bool
        let hasPriorityTier: Bool
    }
}
