import CryptoKit
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

enum QwenBillingCredentialIdentities {
    static let accessKeyID = CredentialIdentity(
        providerID: .qwen,
        accountID: "billing-access-key-id"
    )
    static let accessKeySecret = CredentialIdentity(
        providerID: .qwen,
        accountID: "billing-access-key-secret"
    )
    static let productCode = CredentialIdentity(
        providerID: .qwen,
        accountID: "billing-product-code"
    )

    static let all = [accessKeyID, accessKeySecret, productCode]
}

struct QwenBillingCredentials: Equatable, Sendable {
    let accessKeyID: String
    let accessKeySecret: String
    let productCode: String

    init?(store: any CredentialStoring) throws {
        let values = try QwenBillingCredentialIdentities.all.map { identity -> String in
            do {
                return try store.read(for: identity).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch KeychainStoreError.itemNotFound {
                return ""
            }
        }

        if values.allSatisfy(\.isEmpty) {
            return nil
        }
        guard values.allSatisfy({ !$0.isEmpty }) else {
            throw ProviderClientError.insufficientPermissions
        }

        accessKeyID = values[0]
        accessKeySecret = values[1]
        productCode = values[2]
    }
}

struct AlibabaCloudV3Signer: Sendable {
    private static let algorithm = "ACS3-HMAC-SHA256"
    private static let signedHeaderNames = [
        "host",
        "x-acs-action",
        "x-acs-content-sha256",
        "x-acs-date",
        "x-acs-signature-nonce",
        "x-acs-version"
    ]

    func makeRequest(
        method: HTTPMethod,
        endpoint: URL,
        action: String,
        version: String,
        queryItems: [URLQueryItem],
        accessKeyID: String,
        accessKeySecret: String,
        date: Date,
        nonce: String
    ) throws -> HTTPRequest {
        guard
            endpoint.scheme?.lowercased() == "https",
            endpoint.user == nil,
            endpoint.password == nil,
            endpoint.query == nil,
            endpoint.fragment == nil,
            let host = endpoint.host?.lowercased(),
            !host.isEmpty,
            !accessKeyID.isEmpty,
            !accessKeySecret.isEmpty,
            !nonce.isEmpty
        else {
            throw ProviderClientError.malformedResponse
        }

        let canonicalQuery = Self.canonicalQuery(queryItems)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = canonicalQuery
        guard let url = components?.url else {
            throw ProviderClientError.malformedResponse
        }

        let payloadHash = Self.sha256Hex(Data())
        let headers = [
            "host": host,
            "x-acs-action": action,
            "x-acs-content-sha256": payloadHash,
            "x-acs-date": Self.timestamp(date),
            "x-acs-signature-nonce": nonce,
            "x-acs-version": version
        ]
        let signedHeaders = Self.signedHeaderNames.joined(separator: ";")
        let canonicalHeaders = Self.signedHeaderNames.map { name in
            "\(name):\(headers[name]!)"
        }.joined(separator: "\n")
        let endpointPath = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        )?.percentEncodedPath ?? endpoint.path
        let canonicalURI = endpointPath.isEmpty ? "/" : endpointPath
        let canonicalRequest = [
            method.rawValue,
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            "",
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")
        let stringToSign = "\(Self.algorithm)\n\(Self.sha256Hex(Data(canonicalRequest.utf8)))"
        let signature = Self.hmacSHA256Hex(
            key: Data(accessKeySecret.utf8),
            message: Data(stringToSign.utf8)
        )
        var requestHeaders = headers
        requestHeaders["Authorization"] = "\(Self.algorithm) Credential=\(accessKeyID),SignedHeaders=\(signedHeaders),Signature=\(signature)"
        requestHeaders["Accept"] = "application/json"

        return try HTTPRequest(
            method: method,
            url: url,
            allowedOrigin: try HTTPOrigin(httpsURL: endpoint),
            headers: requestHeaders
        )
    }

    private static func canonicalQuery(_ items: [URLQueryItem]) -> String {
        let encodedItems = items.map { item in
            (percentEncode(item.name), percentEncode(item.value ?? ""))
        }
        let sortedItems = encodedItems.sorted { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }
        return sortedItems.map { item in
            item.0 + "=" + item.1
        }.joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved) ?? ""
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacSHA256Hex(key: Data, message: Data) -> String {
        HMAC<SHA256>.authenticationCode(
            for: message,
            using: SymmetricKey(data: key)
        ).map { String(format: "%02x", $0) }.joined()
    }
}

struct QwenProvider: ProviderClient, Sendable {
    let providerID: ProviderID = .qwen
    let capabilities: Set<ProviderCapability> = [
        .credentialValidation,
        .officialCostHistory
    ]

    private static let billingEndpoint = URL(string: "https://business.aliyuncs.com/")!
    private static let billingAction = "QueryAccountBill"
    private static let billingVersion = "2017-12-14"

    private let httpClient: any HTTPClient
    private let endpointStore: any ProviderEndpointStoring
    private let credentialStore: any CredentialStoring
    private let now: @Sendable () -> Date
    private let nonce: @Sendable () -> String
    private let signer = AlibabaCloudV3Signer()

    init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        endpointStore: any ProviderEndpointStoring = UserDefaultsProviderEndpointStore(),
        credentialStore: any CredentialStoring = KeychainStore(),
        now: @escaping @Sendable () -> Date = Date.init,
        nonce: @escaping @Sendable () -> String = { UUID().uuidString.replacingOccurrences(of: "-", with: "") }
    ) {
        self.httpClient = httpClient
        self.endpointStore = endpointStore
        self.credentialStore = credentialStore
        self.now = now
        self.nonce = nonce
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

            guard let billingCredentials = try QwenBillingCredentials(store: credentialStore) else {
                return try validationSnapshot()
            }
            guard let interval = request.reportingInterval, interval.start < interval.end else {
                throw ProviderClientError.malformedResponse
            }

            return try await billingSnapshot(
                interval: interval,
                credentials: billingCredentials
            )
        } catch let error as ProviderClientError {
            throw error
        } catch is QwenAPIEndpointError {
            throw ProviderClientError.malformedResponse
        } catch KeychainStoreError.locked {
            throw KeychainStoreError.locked
        } catch {
            throw ProviderClientError.malformedResponse
        }
    }

    private func validationSnapshot() throws -> ProviderSnapshot {
        try ProviderSnapshot(
            providerID: providerID,
            capabilities: [.credentialValidation],
            fetchedAt: now(),
            coverage: nil,
            buckets: [],
            balances: [],
            issue: nil
        )
    }

    private func billingSnapshot(
        interval: DateInterval,
        credentials: QwenBillingCredentials
    ) async throws -> ProviderSnapshot {
        let dayIntervals = Self.completeUTCDays(in: interval)
        guard !dayIntervals.isEmpty else {
            throw ProviderClientError.malformedResponse
        }

        var buckets: [PeriodBucket] = []
        var isComplete = true
        for day in dayIntervals {
            let result = try await fetchDailyBill(day: day, credentials: credentials)
            isComplete = isComplete && result.isComplete
            if let money = result.money {
                buckets.append(
                    PeriodBucket(
                        start: day.start,
                        end: day.end,
                        cost: MoneyMetric(value: money, provenance: .official)
                    )
                )
            }
        }

        return try ProviderSnapshot(
            providerID: providerID,
            capabilities: capabilities,
            fetchedAt: now(),
            coverage: ReportingCoverage(
                start: dayIntervals[0].start,
                through: dayIntervals[dayIntervals.count - 1].end,
                completeness: isComplete ? .complete : .partial
            ),
            buckets: buckets,
            balances: [],
            issue: isComplete ? nil : .partialData
        )
    }

    private func fetchDailyBill(
        day: DateInterval,
        credentials: QwenBillingCredentials
    ) async throws -> DailyBillResult {
        let request = try signer.makeRequest(
            method: .get,
            endpoint: Self.billingEndpoint,
            action: Self.billingAction,
            version: Self.billingVersion,
            queryItems: [
                URLQueryItem(name: "BillingCycle", value: Self.billingCycle(day.start)),
                URLQueryItem(name: "BillingDate", value: Self.billingDate(day.start)),
                URLQueryItem(name: "Granularity", value: "DAILY"),
                URLQueryItem(name: "IsGroupByProduct", value: "true"),
                URLQueryItem(name: "PageNum", value: "1"),
                URLQueryItem(name: "PageSize", value: "300"),
                URLQueryItem(name: "ProductCode", value: credentials.productCode)
            ],
            accessKeyID: credentials.accessKeyID,
            accessKeySecret: credentials.accessKeySecret,
            date: now(),
            nonce: nonce()
        )

        do {
            let response = try await httpClient.send(request)
            let payload = try JSONDecoder().decode(AccountBillResponse.self, from: response.body)
            guard payload.success, payload.code.caseInsensitiveCompare("Success") == .orderedSame else {
                throw ProviderClientError.unavailable
            }

            let items = payload.data.items.item
            let currencies = Set(items.map { $0.currency.uppercased() })
            guard currencies.count <= 1 else {
                throw ProviderClientError.malformedResponse
            }
            let amount = items.reduce(into: Decimal.zero) { $0 += $1.pretaxAmount }
            let money = try currencies.first.map { try Money(amount: amount, currencyCode: $0) }
            return DailyBillResult(
                money: money,
                isComplete: payload.data.totalCount <= items.count
            )
        } catch let error as ProviderClientError {
            throw error
        } catch let error as HTTPClientError {
            throw Self.map(error)
        } catch is DecodingError {
            throw ProviderClientError.malformedResponse
        } catch is Money.ValidationError {
            throw ProviderClientError.malformedResponse
        } catch {
            throw ProviderClientError.unavailable
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

    private static func completeUTCDays(in interval: DateInterval) -> [DateInterval] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var start = calendar.startOfDay(for: interval.start)
        var days: [DateInterval] = []

        while let end = calendar.date(byAdding: .day, value: 1, to: start), end <= interval.end {
            if start >= interval.start {
                days.append(DateInterval(start: start, end: end))
            }
            start = end
        }
        return days
    }

    private static func billingCycle(_ date: Date) -> String {
        dateString(date, format: "yyyy-MM")
    }

    private static func billingDate(_ date: Date) -> String {
        dateString(date, format: "yyyy-MM-dd")
    }

    private static func dateString(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
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

private extension CharacterSet {
    static let rfc3986Unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )
}

private extension QwenProvider {
    struct DailyBillResult: Sendable {
        let money: Money?
        let isComplete: Bool
    }

    struct ModelsResponse: Decodable {
        let data: [Model]
    }

    struct Model: Decodable {
        let id: String
    }

    struct AccountBillResponse: Decodable {
        let code: String
        let success: Bool
        let data: AccountBillData

        enum CodingKeys: String, CodingKey {
            case code = "Code"
            case success = "Success"
            case data = "Data"
        }
    }

    struct AccountBillData: Decodable {
        let totalCount: Int
        let items: AccountBillItems

        enum CodingKeys: String, CodingKey {
            case totalCount = "TotalCount"
            case items = "Items"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount) ?? 0
            items = try container.decodeIfPresent(AccountBillItems.self, forKey: .items)
                ?? AccountBillItems(item: [])
        }
    }

    struct AccountBillItems: Decodable {
        let item: [AccountBillItem]

        enum CodingKeys: String, CodingKey {
            case item = "Item"
        }

        init(item: [AccountBillItem]) {
            self.item = item
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            item = try container.decodeIfPresent([AccountBillItem].self, forKey: .item) ?? []
        }
    }

    struct AccountBillItem: Decodable {
        let currency: String
        let pretaxAmount: Decimal

        enum CodingKeys: String, CodingKey {
            case currency = "Currency"
            case pretaxAmount = "PretaxAmount"
        }
    }
}
