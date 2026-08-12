import Foundation
import Security

enum GeminiMonitoringCredentialIdentities {
    static let serviceAccountJSON = CredentialIdentity(
        providerID: .gemini,
        accountID: "google-cloud-monitoring-service-account"
    )

    static let all = [serviceAccountJSON]
}

enum GeminiMonitoringCredentialError: Error, Equatable {
    case invalidJSON
}

struct GeminiMonitoringCredentials: Equatable, Sendable {
    let projectID: String
    let clientEmail: String
    let privateKey: String

    init?(store: any CredentialStoring) throws {
        let json: String
        do {
            json = try store.read(for: GeminiMonitoringCredentialIdentities.serviceAccountJSON)
        } catch KeychainStoreError.itemNotFound {
            return nil
        }
        try self.init(json: json)
    }

    init(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw GeminiMonitoringCredentialError.invalidJSON
        }

        let file: ServiceAccountFile
        do {
            file = try JSONDecoder().decode(ServiceAccountFile.self, from: data)
        } catch {
            throw GeminiMonitoringCredentialError.invalidJSON
        }

        let projectID = file.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientEmail = file.clientEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let privateKey = file.privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            file.type == "service_account",
            projectID.range(
                of: #"^[a-z][a-z0-9-]{4,28}[a-z0-9]$"#,
                options: .regularExpression
            ) != nil,
            !clientEmail.isEmpty,
            clientEmail.hasSuffix(".iam.gserviceaccount.com"),
            privateKey.contains("-----BEGIN PRIVATE KEY-----"),
            privateKey.contains("-----END PRIVATE KEY-----")
        else {
            throw GeminiMonitoringCredentialError.invalidJSON
        }

        self.projectID = projectID
        self.clientEmail = clientEmail
        self.privateKey = privateKey
    }
}

struct GeminiProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .gemini
    let capabilities: Set<ProviderCapability> = [
        .credentialValidation,
        .tokenUsage,
        .modelBreakdown
    ]

    private let httpClient: any HTTPClient
    private let credentialStore: any CredentialStoring
    private let now: @Sendable () -> Date
    private let accessTokenProvider: @Sendable (GeminiMonitoringCredentials) async throws -> String

    init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        credentialStore: any CredentialStoring = KeychainStore(),
        now: @escaping @Sendable () -> Date = Date.init,
        accessTokenProvider: (@Sendable (GeminiMonitoringCredentials) async throws -> String)? = nil
    ) {
        self.httpClient = httpClient
        self.credentialStore = credentialStore
        self.now = now
        self.accessTokenProvider = accessTokenProvider ?? { credentials in
            try await GeminiOAuthTokenClient(httpClient: httpClient)
                .fetchAccessToken(credentials: credentials)
        }
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
            guard
                request.purpose != .credentialValidation,
                let interval = request.reportingInterval,
                let monitoringCredentials = try GeminiMonitoringCredentials(store: credentialStore)
            else {
                return try connectionOnlySnapshot()
            }

            let accessToken = try await accessTokenProvider(monitoringCredentials)
            async let inputSeries = fetchTimeSeries(
                metricType: Self.freeTierInputTokenMetric,
                interval: interval,
                credentials: monitoringCredentials,
                accessToken: accessToken
            )
            async let paidTierOneInputSeries = fetchTimeSeries(
                metricType: Self.paidTierOneInputTokenMetric,
                interval: interval,
                credentials: monitoringCredentials,
                accessToken: accessToken
            )
            async let paidTierTwoInputSeries = fetchTimeSeries(
                metricType: Self.paidTierTwoInputTokenMetric,
                interval: interval,
                credentials: monitoringCredentials,
                accessToken: accessToken
            )
            async let paidTierThreeInputSeries = fetchTimeSeries(
                metricType: Self.paidTierThreeInputTokenMetric,
                interval: interval,
                credentials: monitoringCredentials,
                accessToken: accessToken
            )
            async let outputSeries = fetchTimeSeries(
                metricType: Self.outputTokenMetric,
                interval: interval,
                credentials: monitoringCredentials,
                accessToken: accessToken
            )

            let allInputSeries = try await inputSeries
                + paidTierOneInputSeries
                + paidTierTwoInputSeries
                + paidTierThreeInputSeries
            return try usageSnapshot(
                interval: interval,
                inputSeries: allInputSeries,
                outputSeries: try await outputSeries
            )
        } catch let error as ProviderClientError {
            throw error
        } catch is GeminiMonitoringCredentialError {
            throw ProviderClientError.invalidCredential
        } catch is GeminiServiceAccountJWT.Error {
            throw ProviderClientError.invalidCredential
        } catch {
            throw ProviderClientError.malformedResponse
        }
    }

    private func connectionOnlySnapshot() throws -> ProviderSnapshot {
        try ProviderSnapshot(
            providerID: providerID,
            capabilities: capabilities,
            fetchedAt: now(),
            coverage: nil,
            buckets: [],
            balances: [],
            issue: nil
        )
    }

    private func usageSnapshot(
        interval: DateInterval,
        inputSeries: [TimeSeries],
        outputSeries: [TimeSeries]
    ) throws -> ProviderSnapshot {
        var usage: [GeminiUsageKey: GeminiUsageValue] = [:]
        append(inputSeries, to: &usage) { value, current in
            current.input += value
        }
        append(outputSeries, to: &usage) { value, current in
            current.output += value
        }

        let calendar = Self.utcCalendar
        let groupedByDay = Dictionary(grouping: usage.keys, by: \.day)
        let buckets = groupedByDay.keys.sorted().compactMap { day -> PeriodBucket? in
            let keys = groupedByDay[day, default: []].sorted { $0.model < $1.model }
            let modelBreakdown = keys.compactMap { key -> ModelUsage? in
                guard let value = usage[key], value.input > 0 || value.output > 0 else { return nil }
                return ModelUsage(
                    modelID: key.model,
                    cost: nil,
                    tokenUsage: TokenUsage(
                        inputTokens: value.input,
                        outputTokens: value.output,
                        cachedInputTokens: 0,
                        provenance: .official
                    )
                )
            }
            guard !modelBreakdown.isEmpty else { return nil }
            let total = modelBreakdown.reduce(into: (input: Int64(0), output: Int64(0))) {
                $0.input += $1.tokenUsage?.inputTokens ?? 0
                $0.output += $1.tokenUsage?.outputTokens ?? 0
            }
            return PeriodBucket(
                start: day,
                end: calendar.date(byAdding: .day, value: 1, to: day)!,
                tokenUsage: TokenUsage(
                    inputTokens: total.input,
                    outputTokens: total.output,
                    cachedInputTokens: 0,
                    provenance: .official
                ),
                modelBreakdown: modelBreakdown
            )
        }

        return try ProviderSnapshot(
            providerID: providerID,
            capabilities: capabilities,
            fetchedAt: now(),
            coverage: ReportingCoverage(
                start: interval.start,
                through: interval.end,
                completeness: .complete
            ),
            buckets: buckets,
            balances: [],
            issue: nil
        )
    }

    private func append(
        _ series: [TimeSeries],
        to usage: inout [GeminiUsageKey: GeminiUsageValue],
        update: (Int64, inout GeminiUsageValue) -> Void
    ) {
        for timeSeries in series {
            let model = timeSeries.metric.labels?["model"] ?? "Unknown model"
            for point in timeSeries.points ?? [] {
                guard let end = Self.parseDate(point.interval.endTime) else { continue }
                let day = Self.utcCalendar.startOfDay(for: end.addingTimeInterval(-0.001))
                let key = GeminiUsageKey(day: day, model: model)
                var current = usage[key, default: GeminiUsageValue()]
                update(point.value.int64, &current)
                usage[key] = current
            }
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

    private func fetchTimeSeries(
        metricType: String,
        interval: DateInterval,
        credentials: GeminiMonitoringCredentials,
        accessToken: String
    ) async throws -> [TimeSeries] {
        var result: [TimeSeries] = []
        var pageToken: String?

        repeat {
            guard var components = URLComponents(string: "https://monitoring.googleapis.com") else {
                throw ProviderClientError.malformedResponse
            }
            components.path = "/v3/projects/\(credentials.projectID)/timeSeries"
            components.queryItems = [
                URLQueryItem(name: "filter", value: "metric.type=\"\(metricType)\""),
                URLQueryItem(name: "interval.startTime", value: Self.formatDate(interval.start)),
                URLQueryItem(name: "interval.endTime", value: Self.formatDate(interval.end)),
                URLQueryItem(name: "view", value: "FULL"),
                URLQueryItem(name: "pageSize", value: "1000")
            ]
            if let pageToken, !pageToken.isEmpty {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
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
                        "Authorization": "Bearer \(accessToken)",
                        "Accept": "application/json"
                    ]
                )
                let response = try await httpClient.send(request)
                let page = try JSONDecoder().decode(TimeSeriesResponse.self, from: response.body)
                result.append(contentsOf: page.timeSeries ?? [])
                pageToken = page.nextPageToken
            } catch let error as HTTPClientError {
                throw Self.map(error)
            } catch is DecodingError {
                throw ProviderClientError.malformedResponse
            }
        } while pageToken?.isEmpty == false

        return result
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

    private static func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let freeTierInputTokenMetric =
        "generativelanguage.googleapis.com/quota/generate_content_free_tier_input_token_count/usage"
    private static let paidTierOneInputTokenMetric =
        "generativelanguage.googleapis.com/quota/generate_content_paid_tier_input_token_count/usage"
    private static let paidTierTwoInputTokenMetric =
        "generativelanguage.googleapis.com/quota/generate_content_paid_tier_2_input_token_count/usage"
    private static let paidTierThreeInputTokenMetric =
        "generativelanguage.googleapis.com/quota/generate_content_paid_tier_3_input_token_count/usage"
    private static let outputTokenMetric =
        "generativelanguage.googleapis.com/generate_content_usage_output_token_count"
}

private struct GeminiUsageKey: Hashable {
    let day: Date
    let model: String
}

private struct GeminiUsageValue {
    var input: Int64 = 0
    var output: Int64 = 0
}

private extension GeminiMonitoringCredentials {
    struct ServiceAccountFile: Decodable {
        let type: String
        let projectID: String
        let privateKey: String
        let clientEmail: String

        enum CodingKeys: String, CodingKey {
            case type
            case projectID = "project_id"
            case privateKey = "private_key"
            case clientEmail = "client_email"
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

    struct TimeSeriesResponse: Decodable {
        let timeSeries: [TimeSeries]?
        let nextPageToken: String?
    }
}

private struct TimeSeries: Decodable {
    let metric: Metric
    let points: [Point]?

    struct Metric: Decodable {
        let labels: [String: String]?
    }

    struct Point: Decodable {
        let interval: Interval
        let value: Value
    }

    struct Interval: Decodable {
        let endTime: String
    }

    struct Value: Decodable {
        let int64Value: String?
        let doubleValue: Double?

        var int64: Int64 {
            if let int64Value, let value = Int64(int64Value) { return value }
            if let doubleValue { return Int64(doubleValue) }
            return 0
        }
    }
}

private struct GeminiOAuthTokenClient: Sendable {
    private let httpClient: any HTTPClient

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchAccessToken(credentials: GeminiMonitoringCredentials) async throws -> String {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        let assertion = try GeminiServiceAccountJWT.make(credentials: credentials)
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(
                name: "grant_type",
                value: "urn:ietf:params:oauth:grant-type:jwt-bearer"
            ),
            URLQueryItem(name: "assertion", value: assertion)
        ]
        guard let body = form.percentEncodedQuery?.data(using: .utf8) else {
            throw ProviderClientError.malformedResponse
        }

        do {
            let request = try HTTPRequest(
                method: .post,
                url: url,
                allowedOrigin: try HTTPOrigin(httpsURL: url),
                headers: [
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Accept": "application/json"
                ],
                body: body
            )
            let response = try await httpClient.send(request)
            let token = try JSONDecoder().decode(TokenResponse.self, from: response.body)
            guard !token.accessToken.isEmpty else { throw ProviderClientError.invalidCredential }
            return token.accessToken
        } catch let error as HTTPClientError {
            switch error {
            case let .httpStatus(response) where response.statusCode == 400 || response.statusCode == 401:
                throw ProviderClientError.invalidCredential
            default:
                throw ProviderClientError.unavailable
            }
        } catch is DecodingError {
            throw ProviderClientError.malformedResponse
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }
}

enum GeminiServiceAccountJWT {
    enum Error: Swift.Error {
        case invalidPrivateKey
        case signingFailed
    }

    static func make(credentials: GeminiMonitoringCredentials, now: Date = Date()) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT"])
        let issuedAt = Int(now.timeIntervalSince1970)
        let claims = try JSONSerialization.data(withJSONObject: [
            "iss": credentials.clientEmail,
            "scope": "https://www.googleapis.com/auth/monitoring.read",
            "aud": "https://oauth2.googleapis.com/token",
            "iat": issuedAt,
            "exp": issuedAt + 3_600
        ])
        let signingInput = "\(base64URL(header)).\(base64URL(claims))"
        let keyData = try rsaKeyData(from: credentials.privateKey)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        var keyError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &keyError) else {
            throw Error.invalidPrivateKey
        }
        var signingError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            &signingError
        ) as Data? else {
            throw Error.signingFailed
        }
        return "\(signingInput).\(base64URL(signature))"
    }

    private static func rsaKeyData(from pem: String) throws -> Data {
        let base64 = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let pkcs8 = Data(base64Encoded: base64) else { throw Error.invalidPrivateKey }

        var reader = DERReader(data: pkcs8)
        let sequence = try reader.read(tag: 0x30)
        var sequenceReader = DERReader(data: sequence)
        _ = try sequenceReader.read(tag: 0x02)
        _ = try sequenceReader.read(tag: 0x30)
        return try sequenceReader.read(tag: 0x04)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private struct DERReader {
        private let bytes: [UInt8]
        private var index = 0

        init(data: Data) {
            bytes = Array(data)
        }

        mutating func read(tag expectedTag: UInt8) throws -> Data {
            guard index < bytes.count, bytes[index] == expectedTag else {
                throw Error.invalidPrivateKey
            }
            index += 1
            let length = try readLength()
            guard length >= 0, index <= bytes.count - length else {
                throw Error.invalidPrivateKey
            }
            defer { index += length }
            return Data(bytes[index..<(index + length)])
        }

        private mutating func readLength() throws -> Int {
            guard index < bytes.count else { throw Error.invalidPrivateKey }
            let first = bytes[index]
            index += 1
            if first & 0x80 == 0 { return Int(first) }

            let count = Int(first & 0x7f)
            guard count > 0, count <= 4, index <= bytes.count - count else {
                throw Error.invalidPrivateKey
            }
            var length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
            return length
        }
    }
}
