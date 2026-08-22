import Foundation

struct OpenAIProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .openAI
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
        let usageResult = try await fetchUsage(
            interval: interval,
            credential: credential,
            pageLimit: pageLimit
        )
        let isComplete = costResult.isComplete && usageResult.isComplete

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
                    usage: usageResult.buckets
                ),
                balances: [],
                issue: isComplete ? nil : .partialData
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
                path: "/v1/organization/costs",
                interval: interval,
                credential: credential,
                pageToken: pageToken,
                groupByModel: false
            )

            for bucket in page.data {
                let key = BucketKey(start: bucket.startTime, end: bucket.endTime)
                for result in bucket.results {
                    var aggregate = buckets[key] ?? CostBucket(
                        startTime: bucket.startTime,
                        endTime: bucket.endTime,
                        amount: 0,
                        currency: result.amount.currency
                    )
                    guard aggregate.currency.caseInsensitiveCompare(result.amount.currency) == .orderedSame else {
                        throw ProviderClientError.malformedResponse
                    }
                    aggregate.amount += result.amount.value.value
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
    ) async throws -> PageResult<UsageBucket> {
        var pageToken: String?
        var buckets: [BucketKey: UsageBucket] = [:]

        for pageIndex in 0..<pageLimit {
            let page: Page<UsageResult> = try await fetchPage(
                path: "/v1/organization/usage/completions",
                interval: interval,
                credential: credential,
                pageToken: pageToken,
                groupByModel: true
            )

            for bucket in page.data {
                let key = BucketKey(start: bucket.startTime, end: bucket.endTime)
                var aggregate = buckets[key] ?? UsageBucket(
                    startTime: bucket.startTime,
                    endTime: bucket.endTime
                )
                for result in bucket.results {
                    let tokens = TokenCount(
                        input: result.inputTokens,
                        output: result.outputTokens,
                        cachedInput: result.inputCachedTokens
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

    private func fetchPage<Result: Decodable>(
        path: String,
        interval: DateInterval,
        credential: String,
        pageToken: String?,
        groupByModel: Bool
    ) async throws -> Page<Result> {
        guard var components = URLComponents(string: "https://api.openai.com\(path)") else {
            throw ProviderClientError.malformedResponse
        }
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int64(interval.start.timeIntervalSince1970))),
            URLQueryItem(name: "end_time", value: String(Int64(interval.end.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]
        if groupByModel {
            components.queryItems?.append(URLQueryItem(name: "group_by", value: "model"))
        }
        if let pageToken {
            components.queryItems?.append(URLQueryItem(name: "page", value: pageToken))
        }
        guard let url = components.url else {
            throw ProviderClientError.malformedResponse
        }

        do {
            let origin = try HTTPOrigin(httpsURL: url)
            let request = try HTTPRequest(
                method: .get,
                url: url,
                allowedOrigin: origin,
                headers: [
                    "Authorization": "Bearer \(credential)",
                    "Accept": "application/json"
                ]
            )
            let response = try await httpClient.send(request)
            guard (200...299).contains(response.statusCode) else {
                throw HTTPClientError.httpStatus(response)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
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
                    value: try Money(amount: bucket.amount, currencyCode: bucket.currency),
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
                start: Date(timeIntervalSince1970: TimeInterval(key.start)),
                end: Date(timeIntervalSince1970: TimeInterval(key.end)),
                cost: cost,
                tokenUsage: tokenUsage,
                modelBreakdown: models
            )
        }
    }

    private static func tokenUsage(from tokens: TokenCount) -> TokenUsage {
        TokenUsage(
            inputTokens: tokens.input,
            outputTokens: tokens.output,
            cachedInputTokens: tokens.cachedInput,
            provenance: .official
        )
    }

    private static func pageLimit(for purpose: ProviderFetchRequest.Purpose) -> Int {
        switch purpose {
        case .credentialValidation: 1
        case .incremental: 2
        case .full: 10
        }
    }

}

private extension OpenAIProvider {
    struct Page<Result: Decodable>: Decodable {
        let data: [APIBucket<Result>]
        let hasMore: Bool
        let nextPage: String?
    }

    struct APIBucket<Result: Decodable>: Decodable {
        let startTime: Int64
        let endTime: Int64
        let results: [Result]
    }

    struct CostResult: Decodable {
        let amount: Amount
    }

    struct Amount: Decodable {
        let value: FlexibleDecimal
        let currency: String
    }

    struct UsageResult: Decodable {
        let model: String?
        let inputTokens: Int64
        let outputTokens: Int64
        let inputCachedTokens: Int64
    }

    struct FlexibleDecimal: Decodable {
        let value: Decimal

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let decimal = try? container.decode(Decimal.self) {
                value = decimal
                return
            }
            if let string = try? container.decode(String.self) {
                if let decimal = Decimal(
                    string: string,
                    locale: Locale(identifier: "en_US_POSIX")
                ) {
                    value = decimal
                    return
                }
                if Self.isScientificZero(string) {
                    value = .zero
                    return
                }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a base-10 decimal number or string."
            )
        }

        private static func isScientificZero(_ string: String) -> Bool {
            let parts = string.split(
                omittingEmptySubsequences: false,
                whereSeparator: { $0 == "e" || $0 == "E" }
            )
            guard
                parts.count == 2,
                Decimal(
                    string: String(parts[0]),
                    locale: Locale(identifier: "en_US_POSIX")
                ) == .zero
            else { return false }

            let exponent = parts[1]
            let digits = exponent.first == "+" || exponent.first == "-"
                ? exponent.dropFirst()
                : exponent[...]
            return !digits.isEmpty && digits.allSatisfy { $0.isNumber }
        }
    }

    struct BucketKey: Hashable {
        let start: Int64
        let end: Int64
    }

    struct CostBucket {
        let startTime: Int64
        let endTime: Int64
        var amount: Decimal
        let currency: String
    }

    struct UsageBucket {
        let startTime: Int64
        let endTime: Int64
        var total = TokenCount()
        var models: [String: TokenCount] = [:]
    }

    struct TokenCount {
        var input: Int64 = 0
        var output: Int64 = 0
        var cachedInput: Int64 = 0

        mutating func add(_ other: TokenCount) throws {
            input = try Self.adding(input, other.input)
            output = try Self.adding(output, other.output)
            cachedInput = try Self.adding(cachedInput, other.cachedInput)
        }

        private static func adding(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
            let result = lhs.addingReportingOverflow(rhs)
            guard !result.overflow else { throw ProviderClientError.malformedResponse }
            return result.partialValue
        }
    }

    struct PageResult<Bucket> {
        let buckets: [BucketKey: Bucket]
        let isComplete: Bool
    }
}
