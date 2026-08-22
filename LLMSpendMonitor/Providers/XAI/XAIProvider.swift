import Foundation

struct XAIProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .xAI
    let capabilities: Set<ProviderCapability> = [
        .balance,
        .officialCostHistory,
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
        let credential = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else {
            throw ProviderClientError.invalidCredential
        }
        guard let interval = request.reportingInterval, interval.start < interval.end else {
            throw ProviderClientError.malformedResponse
        }

        do {
            let teamID = try await fetchTeamID(credential: credential)
            var balance: BalanceResponse?
            var balanceError: ProviderClientError?
            do {
                balance = try await fetchBalance(teamID: teamID, credential: credential)
            } catch let error as ProviderClientError {
                balanceError = error
            }

            var usage: UsageResponse?
            var usageError: ProviderClientError?
            do {
                usage = try await fetchUsage(
                    teamID: teamID,
                    interval: interval,
                    credential: credential
                )
            } catch let error as ProviderClientError {
                usageError = error
            }

            guard balance != nil || usage != nil else {
                throw balanceError ?? usageError ?? ProviderClientError.unavailable
            }

            let coverage = usage.map {
                ReportingCoverage(
                    start: interval.start,
                    through: interval.end,
                    completeness: $0.limitReached ? .partial : .complete
                )
            }
            let buckets = try usage.map {
                try Self.makeBuckets(from: $0, interval: interval)
            } ?? []
            let balances = try balance.map { [try Self.makeBalance($0)] } ?? []
            let issue: ProviderIssue? = if balance == nil {
                .balanceUnavailable
            } else if usage == nil || usage?.limitReached == true {
                .partialData
            } else {
                nil
            }

            return try ProviderSnapshot(
                providerID: providerID,
                capabilities: capabilities,
                fetchedAt: now(),
                coverage: coverage,
                buckets: buckets,
                balances: balances,
                issue: issue
            )
        } catch let error as ProviderClientError {
            throw error
        } catch is DecodingError {
            throw ProviderClientError.malformedResponse
        } catch {
            throw ProviderClientError.malformedResponse
        }
    }

    private func fetchTeamID(credential: String) async throws -> String {
        let response: ManagementKeyResponse = try await send(
            method: .get,
            path: "/auth/management-keys/validation",
            credential: credential
        )
        if let scope = response.scope, scope != "SCOPE_TEAM" {
            throw ProviderClientError.insufficientPermissions
        }
        if response.scope == "SCOPE_TEAM" {
            if let scopeID = response.scopeID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !scopeID.isEmpty {
                return scopeID
            }
            if let teamID = response.teamID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !teamID.isEmpty {
                return teamID
            }
        }
        if response.scope == nil,
           let teamID = response.teamID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !teamID.isEmpty {
            return teamID
        }
        throw ProviderClientError.insufficientPermissions
    }

    private func fetchBalance(
        teamID: String,
        credential: String
    ) async throws -> BalanceResponse {
        try await send(
            method: .get,
            path: "/v1/billing/teams/\(teamID)/prepaid/balance",
            credential: credential
        )
    }

    private func fetchUsage(
        teamID: String,
        interval: DateInterval,
        credential: String
    ) async throws -> UsageResponse {
        let dateFormatter = Self.makeUsageRequestDateFormatter()
        let body = UsageRequest(
            analyticsRequest: AnalyticsRequest(
                timeRange: TimeRange(
                    startTime: dateFormatter.string(from: interval.start),
                    endTime: dateFormatter.string(from: interval.end.addingTimeInterval(-1)),
                    timezone: "Etc/GMT"
                ),
                timeUnit: "TIME_UNIT_DAY",
                values: [AnalyticsValue(name: "usd", aggregation: "AGGREGATION_SUM")],
                groupBy: ["description"],
                filters: []
            )
        )
        return try await send(
            method: .post,
            path: "/v1/billing/teams/\(teamID)/usage",
            credential: credential,
            body: try JSONEncoder().encode(body)
        )
    }

    private func send<Response: Decodable>(
        method: HTTPMethod,
        path: String,
        credential: String,
        body: Data? = nil
    ) async throws -> Response {
        guard let url = URL(string: "https://management-api.x.ai\(path)") else {
            throw ProviderClientError.malformedResponse
        }

        do {
            var headers = [
                "Authorization": "Bearer \(credential)",
                "Accept": "application/json"
            ]
            if body != nil {
                headers["Content-Type"] = "application/json"
            }
            let request = try HTTPRequest(
                method: method,
                url: url,
                allowedOrigin: try HTTPOrigin(httpsURL: url),
                headers: headers,
                body: body
            )
            let response = try await httpClient.send(request)
            guard (200...299).contains(response.statusCode) else {
                throw HTTPClientError.httpStatus(response)
            }
            return try JSONDecoder().decode(Response.self, from: response.body)
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

    private static func makeBalance(_ response: BalanceResponse) throws -> ProviderBalance {
        guard let cents = Decimal(
            string: response.total.val,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            throw ProviderClientError.malformedResponse
        }
        let amount = max(-cents / 100, 0)
        return ProviderBalance(
            total: MoneyMetric(
                value: try Money(amount: amount, currencyCode: "USD"),
                provenance: .official
            ),
            granted: nil,
            toppedUp: nil
        )
    }

    private static func makeBuckets(
        from response: UsageResponse,
        interval: DateInterval
    ) throws -> [PeriodBucket] {
        var aggregates: [Date: DayAggregate] = [:]
        let calendar = utcCalendar
        let fractionalTimestampFormatter = ISO8601DateFormatter()
        fractionalTimestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime]

        for series in response.timeSeries {
            let label = series.groupLabels.first ?? series.group.first ?? "Other"
            for point in series.dataPoints {
                guard
                    let value = point.values.first,
                    value >= 0,
                    let timestamp = parseTimestamp(
                        point.timestamp,
                        fractionalFormatter: fractionalTimestampFormatter,
                        formatter: timestampFormatter
                    )
                else {
                    throw ProviderClientError.malformedResponse
                }
                let start = max(timestamp, interval.start)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: timestamp)
                guard let nextDay else {
                    throw ProviderClientError.malformedResponse
                }
                let end = min(nextDay, interval.end)
                guard start < end else { continue }

                var aggregate = aggregates[start] ?? DayAggregate(end: end)
                aggregate.end = max(aggregate.end, end)
                aggregate.total += value
                aggregate.models[label, default: 0] += value
                aggregates[start] = aggregate
            }
        }

        return try aggregates.keys.sorted().map { start in
            guard let aggregate = aggregates[start] else {
                throw ProviderClientError.malformedResponse
            }
            let modelBreakdown = try aggregate.models.keys.sorted().map { model in
                ModelUsage(
                    modelID: model,
                    cost: try money(aggregate.models[model] ?? 0),
                    tokenUsage: nil
                )
            }
            return PeriodBucket(
                start: start,
                end: aggregate.end,
                cost: try money(aggregate.total),
                modelBreakdown: modelBreakdown
            )
        }
    }

    private static func money(_ amount: Decimal) throws -> MoneyMetric {
        MoneyMetric(
            value: try Money(amount: amount, currencyCode: "USD"),
            provenance: .official
        )
    }

    private static func makeUsageRequestDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    private static func parseTimestamp(
        _ value: String,
        fractionalFormatter: ISO8601DateFormatter,
        formatter: ISO8601DateFormatter
    ) -> Date? {
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return formatter.date(from: value)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private extension XAIProvider {
    struct ManagementKeyResponse: Decodable {
        let teamID: String?
        let scope: String?
        let scopeID: String?

        private enum CodingKeys: String, CodingKey {
            case teamID = "teamId"
            case scope
            case scopeID = "scopeId"
        }
    }

    struct BalanceResponse: Decodable {
        let total: Cents
    }

    struct Cents: Decodable {
        let val: String
    }

    struct UsageResponse: Decodable {
        let timeSeries: [TimeSeries]
        let limitReached: Bool
    }

    struct TimeSeries: Decodable {
        let group: [String]
        let groupLabels: [String]
        let dataPoints: [DataPoint]
    }

    struct DataPoint: Decodable {
        let timestamp: String
        let values: [Decimal]
    }

    struct DayAggregate {
        var end: Date
        var total: Decimal = 0
        var models: [String: Decimal] = [:]
    }

    struct UsageRequest: Encodable {
        let analyticsRequest: AnalyticsRequest
    }

    struct AnalyticsRequest: Encodable {
        let timeRange: TimeRange
        let timeUnit: String
        let values: [AnalyticsValue]
        let groupBy: [String]
        let filters: [String]
    }

    struct TimeRange: Encodable {
        let startTime: String
        let endTime: String
        let timezone: String
    }

    struct AnalyticsValue: Encodable {
        let name: String
        let aggregation: String
    }
}
